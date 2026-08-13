require "rails_helper"
require "pg"
require "rotp"
require "securerandom"

RSpec.describe "Communications and support boundaries", type: :request do
  let(:password) { "Crystell-Support-2026!" }
  let(:unique) { SecureRandom.hex(8) }

  before do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    cleanup_control_plane
    @owner_registration = Auth::AccountRegistration.call(
      email: "support-owner-#{unique}@example.test",
      password: password,
      tenant_name: "Support Tenant #{unique}",
      tenant_slug: "support-tenant-#{unique}",
      store_name: "Support Store #{unique}",
      store_slug: "support-store-#{unique}"
    )
    @member_registration = Auth::AccountRegistration.call(
      email: "support-member-#{unique}@example.test",
      password: password,
      tenant_name: "Member Personal #{unique}",
      tenant_slug: "member-personal-#{unique}",
      store_name: "Member Store #{unique}",
      store_slug: "member-store-#{unique}"
    )
    @foreign_registration = Auth::AccountRegistration.call(
      email: "support-foreign-#{unique}@example.test",
      password: password,
      tenant_name: "Foreign Support #{unique}",
      tenant_slug: "foreign-support-#{unique}",
      store_name: "Foreign Store #{unique}",
      store_slug: "foreign-store-#{unique}"
    )
    @owner = IdentityScope.with(@owner_registration.user_id) { User.find(@owner_registration.user_id) }
    @member = IdentityScope.with(@member_registration.user_id) { User.find(@member_registration.user_id) }
    @foreign_owner = IdentityScope.with(@foreign_registration.user_id) { User.find(@foreign_registration.user_id) }

    invitation = nil
    TenantAccess.with(user: @owner, tenant_id: @owner_registration.tenant_id) do
      @store = Store.find_by!(slug: "support-store-#{unique}")
      invitation = Auth::TenantInvitationIssuer.call(email: @member.email, role: "member")
    end
    Auth::TenantInvitationAcceptor.call(user: @member, token: invitation.token)
    TenantAccess.with(user: @foreign_owner, tenant_id: @foreign_registration.tenant_id) do
      @foreign_store = Store.find_by!(slug: "foreign-store-#{unique}")
    end

    @owner_token = Auth::SessionIssuer.call(user_id: @owner.id).token
    @member_token = Auth::SessionIssuer.call(user_id: @member.id).token
    @foreign_token = Auth::SessionIssuer.call(user_id: @foreign_owner.id).token
  end

  after do
    cleanup_tenant_records
    cleanup_control_plane
    @admin&.close
    Current.reset
    ControlPlaneCurrent.reset
  end

  it "lets a member create and continue only their tenant-scoped support conversation" do
    post tickets_path,
         params: { subject: "مشكلة في إعداد الشحن", body: "أحتاج مساعدة في إعداد شركة الشحن", priority: "high" },
         headers: tenant_headers(@member_token),
         as: :json
    expect(response).to have_http_status(:created)
    ticket = response.parsed_body.fetch("support_ticket")
    @ticket_id = ticket.fetch("id")
    expect(ticket.fetch("ticket_number")).to start_with("SUP-")

    post "#{tickets_path}/#{@ticket_id}/messages",
         params: { body: "هذه تفاصيل إضافية للمشكلة" },
         headers: tenant_headers(@member_token),
         as: :json
    expect(response).to have_http_status(:created)

    get "#{tickets_path}/#{@ticket_id}", headers: tenant_headers(@member_token)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("support_ticket", "messages").length).to eq(2)

    patch "#{tickets_path}/#{@ticket_id}",
          params: { status: "resolved" },
          headers: tenant_headers(@member_token),
          as: :json
    expect(response).to have_http_status(:forbidden)

    get "/v1/stores/#{@foreign_store.id}/support/tickets/#{@ticket_id}",
        headers: foreign_headers(@foreign_token)
    expect(response).to have_http_status(:not_found)
  end

  it "uploads support images and video through tenant storage and keeps messages append-only" do
    ticket = create_ticket
    upload = nil

    begin
      TenantAccess.with(user: @member, tenant_id: @owner_registration.tenant_id) do
        upload = Support::AttachmentManager.issue_upload(
          store_id: @store.id,
          ticket_id: ticket.id,
          filename: "screen shot.png",
          content_type: "image/png",
          byte_size: 12
        )
        expect(upload.object_key).to start_with("tenants/#{@owner_registration.tenant_id}/stores/#{@store.id}/support/")

        Storage::ObjectStore.internal_client.put_object(
          bucket: Storage::ObjectStore.bucket,
          key: upload.object_key,
          body: "support-img!",
          content_type: "image/png"
        )
        attachment = Support::AttachmentManager.complete(
          store_id: @store.id,
          ticket_id: ticket.id,
          attachment_id: upload.attachment_id
        )
        message = Support::TicketDesk.reply(
          store_id: @store.id,
          ticket_id: ticket.id,
          body: "أرفقت صورة توضح المشكلة",
          attachment_ids: [attachment.id]
        )
        expect(attachment.reload.support_message_id).to eq(message.id)
        expect(Support::AttachmentManager.preview_url(
          store_id: @store.id,
          ticket_id: ticket.id,
          attachment_id: attachment.id
        )).to include(ENV.fetch("S3_BUCKET"))

        expect { message.update!(body: "tampered") }
          .to raise_error(ActiveRecord::StatementInvalid, /support_messages_are_append_only|permission denied/)
      end
    ensure
      Storage::ObjectStore.delete(key: upload.object_key) if upload
    end
  end

  it "renders and dispatches encrypted provider notifications idempotently" do
    TenantAccess.with(user: @owner, tenant_id: @owner_registration.tenant_id) do
      template = Notifications::TemplateCatalog.upsert(
        store_id: @store.id,
        key: "support.updated",
        channel: "email",
        locale: "ar",
        subject: "تحديث {{ticket_number}}",
        body: "مرحبًا {{name}}، تم تحديث التذكرة {{ticket_number}}.",
        status: "active",
        variables: %w[name ticket_number]
      )
      account = CommunicationProviderAccount.create!(
        tenant_id: Current.tenant_id,
        store_id: @store.id,
        channel: "email",
        provider_key: "reference",
        mode: "test",
        status: "active",
        credentials_ciphertext: Communications::CredentialVault.encrypt({ "api_key" => "never-store-raw" }, purpose: "communication-provider")
      )
      delivery = Notifications::DeliveryQueue.call(
        store_id: @store.id,
        template_key: template.key,
        channel: "email",
        locale: "ar",
        recipient: "CUSTOMER-#{unique}@EXAMPLE.TEST",
        variables: { name: "عمار", ticket_number: "SUP-100" },
        idempotency_key: "support-email-#{unique}"
      )
      expect(delivery.recipient_ciphertext).not_to include("customer-")
      expect(delivery.payload_ciphertext).not_to include("SUP-100")
      expect(delivery.communication_provider_account_id).to eq(account.id)

      replay = Notifications::DeliveryQueue.call(
        store_id: @store.id,
        template_key: template.key,
        channel: "email",
        locale: "ar",
        recipient: "customer-#{unique}@example.test",
        variables: { name: "عمار", ticket_number: "SUP-100" },
        idempotency_key: "support-email-#{unique}"
      )
      expect(replay.id).to eq(delivery.id)

      sent = Notifications::Dispatcher.call(delivery_id: delivery.id)
      expect(sent.status).to eq("sent")
      expect(sent.provider_message_id).to start_with("reference-email-")

      notification = Notifications::Inbox.publish(
        user_id: @owner.id,
        store_id: @store.id,
        kind: "support.updated",
        title: "تم تحديث تذكرتك",
        body: "رد فريق الدعم على طلبك"
      )
      expect(Notifications::Inbox.list.map(&:id)).to include(notification.id)
      expect(Notifications::Inbox.mark_read(notification_id: notification.id).read_at).to be_present
    end
  end

  it "allows an independent control-plane operator to read and answer through bounded capabilities" do
    ticket = create_ticket
    control = ControlPlane::BootstrapOwner.call(
      email: "support-control-#{unique}@example.test",
      password: password
    )
    post "/control/v1/session",
         params: { email: control.user.email, password: password, otp: ROTP::TOTP.new(control.mfa_secret).now },
         as: :json
    expect(response).to have_http_status(:created)
    token = response.parsed_body.fetch("token")

    expect do
      ControlPlaneRecord.connection.select_value("SELECT COUNT(*) FROM support_tickets")
    end.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)

    get "/control/v1/support/tickets", headers: control_headers(token)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("support_tickets").map { |item| item.fetch("id") }).to include(ticket.id)

    post "/control/v1/support/tickets/#{ticket.id}/messages",
         params: { body: "راجعنا إعداداتك وسنساعدك في إكمالها.", reason: "Respond to merchant support request" },
         headers: control_headers(token),
         as: :json
    expect(response).to have_http_status(:created)

    get "/control/v1/support/tickets/#{ticket.id}", headers: control_headers(token)
    expect(response).to have_http_status(:ok)
    thread = response.parsed_body.dig("support_ticket", "messages")
    expect(thread.last).to include("author_type" => "support")
    expect(ControlPlaneAuditEvent.where(action: "control_plane.support_replied").count).to eq(1)
  end

  private

  def create_ticket
    TenantAccess.with(user: @member, tenant_id: @owner_registration.tenant_id) do
      @ticket_id = Support::TicketDesk.create(
        store_id: @store.id,
        subject: "Support request #{unique}",
        body: "Please help with this store configuration"
      ).id
      SupportTicket.find(@ticket_id)
    end
  end

  def tickets_path
    "/v1/stores/#{@store.id}/support/tickets"
  end

  def tenant_headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "X-Crystell-Tenant" => @owner_registration.tenant_id,
      "Accept" => "application/json"
    }
  end

  def foreign_headers(token)
    {
      "Authorization" => "Bearer #{token}",
      "X-Crystell-Tenant" => @foreign_registration.tenant_id,
      "Accept" => "application/json"
    }
  end

  def control_headers(token)
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end

  def cleanup_tenant_records
    return unless @admin && @owner_registration

    tenant_id = @owner_registration.tenant_id
    %w[
      support_attachments support_messages support_tickets notification_deliveries
      notification_templates communication_provider_accounts notifications
    ].each do |table|
      @admin.exec_params("DELETE FROM #{table} WHERE tenant_id = $1::uuid", [tenant_id])
    end
  rescue PG::UndefinedTable
    nil
  end

  def cleanup_control_plane
    return unless @admin

    @admin.exec("DELETE FROM control_plane_audit_events")
    @admin.exec("DELETE FROM control_plane_sessions")
    @admin.exec("DELETE FROM control_plane_users")
  rescue PG::UndefinedTable
    nil
  end
end
