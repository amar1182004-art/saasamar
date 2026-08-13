require "rails_helper"
require "pg"
require "securerandom"

RSpec.describe "Product media" do
  let(:password) { "Crystell-Media-Test-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @registration = Auth::AccountRegistration.call(
      email: "media-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Media Tenant #{unique}",
      tenant_slug: "media-tenant-#{unique}",
      store_name: "Media Store #{unique}",
      store_slug: "media-store-#{unique}"
    )
    @other_registration = Auth::AccountRegistration.call(
      email: "media-other-#{unique}@example.test",
      password: password,
      tenant_name: "Media Other Tenant #{unique}",
      tenant_slug: "media-other-tenant-#{unique}",
      store_name: "Media Other Store #{unique}",
      store_slug: "media-other-store-#{unique}"
    )

    @owner = IdentityScope.with(@registration.user_id) { User.find(@registration.user_id) }
    @other_owner = IdentityScope.with(@other_registration.user_id) { User.find(@other_registration.user_id) }

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      @store = Store.find_by!(slug: "media-store-#{unique}")
      @product = Catalog::ProductCreator.call(
        store_id: @store.id,
        attributes: { title: "Media Product", slug: "media-product-#{unique}" },
        variants: [{ title: "Default", currency: "EGP", price_cents: 10_000 }]
      )
    end
  end

  after do
    tenant_ids = [@registration&.tenant_id, @other_registration&.tenant_id].compact
    unless tenant_ids.empty? || @admin.nil?
      placeholders = tenant_ids.each_index.map { |index| "$#{index + 1}::uuid" }.join(", ")
      @admin.exec_params("DELETE FROM product_media WHERE tenant_id IN (#{placeholders})", tenant_ids)
      @admin.exec_params("DELETE FROM product_variants WHERE tenant_id IN (#{placeholders})", tenant_ids)
      @admin.exec_params("DELETE FROM products WHERE tenant_id IN (#{placeholders})", tenant_ids)
    end

    @admin&.close
    Current.reset
  end

  it "issues a tenant-scoped upload, verifies the object and exposes only a signed preview" do
    upload = nil

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      upload = Catalog::ProductMediaManager.issue_upload(
        store_id: @store.id,
        product_id: @product.id,
        filename: "hero image.jpg",
        content_type: "image/jpeg",
        byte_size: 12,
        alt_text: "Hero image"
      )

      expect(upload.object_key).to start_with("tenants/#{@registration.tenant_id}/stores/#{@store.id}/products/#{upload.media_id}/")
      expect(upload.upload_url).to include(ENV.fetch("S3_BUCKET"))

      Storage::ObjectStore.internal_client.put_object(
        bucket: Storage::ObjectStore.bucket,
        key: upload.object_key,
        body: "hello-media!",
        content_type: "image/jpeg"
      )

      media = Catalog::ProductMediaManager.complete(media_id: upload.media_id, width: 1200, height: 800)
      expect(media.status).to eq("ready")
      expect(media.width).to eq(1200)
      expect(media.height).to eq(800)

      preview_url = Catalog::ProductMediaManager.preview_url(media_id: media.id)
      expect(preview_url).to include(ENV.fetch("S3_BUCKET"))
    end

    TenantAccess.with(user: @other_owner, tenant_id: @other_registration.tenant_id) do
      expect(ProductMedia.find_by(id: upload.media_id)).to be_nil
    end
  ensure
    Storage::ObjectStore.delete(key: upload.object_key) if upload
  rescue Aws::S3::Errors::ServiceError
    nil
  end

  it "rejects unsupported media and oversized declarations before creating storage records" do
    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      expect do
        Catalog::ProductMediaManager.issue_upload(
          store_id: @store.id,
          product_id: @product.id,
          filename: "payload.exe",
          content_type: "application/octet-stream",
          byte_size: 100
        )
      end.to raise_error(Catalog::ProductMediaManager::InvalidMediaError, /unsupported/i)

      expect do
        Catalog::ProductMediaManager.issue_upload(
          store_id: @store.id,
          product_id: @product.id,
          filename: "huge.jpg",
          content_type: "image/jpeg",
          byte_size: ENV.fetch("PRODUCT_IMAGE_MAX_BYTES").to_i + 1
        )
      end.to raise_error(Catalog::ProductMediaManager::InvalidMediaError, /too large/i)
    end
  end

  it "marks mismatched uploads failed and removes the untrusted object" do
    upload = nil

    TenantAccess.with(user: @owner, tenant_id: @registration.tenant_id) do
      upload = Catalog::ProductMediaManager.issue_upload(
        store_id: @store.id,
        product_id: @product.id,
        filename: "mismatch.jpg",
        content_type: "image/jpeg",
        byte_size: 100
      )

      Storage::ObjectStore.internal_client.put_object(
        bucket: Storage::ObjectStore.bucket,
        key: upload.object_key,
        body: "wrong-size",
        content_type: "image/jpeg"
      )

      expect do
        Catalog::ProductMediaManager.complete(media_id: upload.media_id)
      end.to raise_error(Catalog::ProductMediaManager::UploadVerificationError)

      expect(ProductMedia.find(upload.media_id).status).to eq("failed")
      expect do
        Storage::ObjectStore.head(key: upload.object_key)
      end.to raise_error(Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey)
    end
  end
end
