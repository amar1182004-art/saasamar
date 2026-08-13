module Storage
  class ObjectStore
    class ConfigurationError < StandardError; end

    DEFAULT_UPLOAD_TTL = 600
    DEFAULT_READ_TTL = 300

    def self.presigned_put(key:, content_type:, expires_in: DEFAULT_UPLOAD_TTL)
      presigner(public_client).presigned_url(
        :put_object,
        bucket: bucket,
        key: key,
        content_type: content_type,
        expires_in: expires_in
      )
    end

    def self.presigned_get(key:, expires_in: DEFAULT_READ_TTL)
      presigner(public_client).presigned_url(
        :get_object,
        bucket: bucket,
        key: key,
        expires_in: expires_in
      )
    end

    def self.head(key:)
      internal_client.head_object(bucket: bucket, key: key)
    end

    def self.delete(key:)
      internal_client.delete_object(bucket: bucket, key: key)
    end

    def self.bucket
      ENV.fetch("S3_BUCKET")
    rescue KeyError
      raise ConfigurationError, "S3_BUCKET is required"
    end

    def self.internal_client
      build_client(ENV.fetch("S3_ENDPOINT"))
    rescue KeyError
      raise ConfigurationError, "S3_ENDPOINT is required"
    end

    def self.public_client
      endpoint = ENV["S3_PUBLIC_ENDPOINT"].presence || ENV.fetch("S3_ENDPOINT")
      build_client(endpoint)
    rescue KeyError
      raise ConfigurationError, "S3_PUBLIC_ENDPOINT or S3_ENDPOINT is required"
    end

    def self.build_client(endpoint)
      Aws::S3::Client.new(
        endpoint: endpoint,
        region: ENV.fetch("S3_REGION", "us-east-1"),
        credentials: Aws::Credentials.new(
          ENV.fetch("S3_ACCESS_KEY"),
          ENV.fetch("S3_SECRET_KEY")
        ),
        force_path_style: ActiveModel::Type::Boolean.new.cast(ENV.fetch("S3_FORCE_PATH_STYLE", "true"))
      )
    rescue KeyError => error
      raise ConfigurationError, "#{error.key} is required"
    end
    private_class_method :build_client

    def self.presigner(client)
      Aws::S3::Presigner.new(client: client)
    end
    private_class_method :presigner
  end
end
