module Control
  module V1
    class FeatureFlagsController < BaseController
      def index
        flags = ControlPlane::FeatureFlagRegistry.list
        render json: { feature_flags: flags.map { |flag| serialize(flag) } }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      end

      def show
        flag = ControlPlane::FeatureFlagRegistry.read(key: params.require(:key))
        render json: { feature_flag: serialize(flag) }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::FeatureFlagRegistry::InvalidFlagError => error
        render_invalid(error)
      rescue ActiveRecord::RecordNotFound
        render_not_found
      end

      def update
        attributes = flag_attributes
        flag = ControlPlane::FeatureFlagRegistry.upsert(
          key: params.require(:key),
          description: attributes.key?(:description) ? attributes[:description] : nil,
          enabled: attributes.key?(:enabled) ? attributes[:enabled] : nil,
          rollout_percentage: attributes.key?(:rollout_percentage) ? attributes[:rollout_percentage] : nil,
          config: attributes.key?(:config) ? attributes[:config] : nil,
          reason: attributes[:reason],
          request_id: request.request_id,
          ip_address: request.remote_ip
        )
        render json: { feature_flag: serialize(flag) }
      rescue ControlPlane::Permission::ForbiddenError
        render_forbidden
      rescue ControlPlane::FeatureFlagRegistry::ElevationRequiredError
        render json: { error: "privilege_elevation_required" }, status: :conflict
      rescue ControlPlane::FeatureFlagRegistry::InvalidFlagError, ActionController::ParameterMissing => error
        render_invalid(error)
      end

      private

      def flag_attributes
        source = params.require(:feature_flag)
        attributes = source
                     .permit(:description, :enabled, :rollout_percentage, :reason)
                     .to_h
                     .deep_symbolize_keys

        if source.key?(:config)
          raw_config = source[:config]
          attributes[:config] = if raw_config.respond_to?(:to_unsafe_h)
                                  raw_config.to_unsafe_h
                                else
                                  raw_config
                                end
        end

        attributes
      end

      def serialize(flag)
        {
          id: flag.id,
          key: flag.key,
          description: flag.description,
          enabled: flag.enabled,
          rollout_percentage: flag.rollout_percentage,
          config: flag.config,
          lock_version: flag.lock_version,
          updated_at: flag.updated_at
        }
      end

      def render_forbidden
        render json: { error: "control_plane_forbidden" }, status: :forbidden
      end

      def render_invalid(error)
        render json: { error: "feature_flag_validation_failed", details: error.message }, status: :unprocessable_entity
      end

      def render_not_found
        render json: { error: "feature_flag_not_found" }, status: :not_found
      end
    end
  end
end
