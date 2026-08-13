module Support
  class TicketDesk
    class MissingTenantContextError < StandardError; end
    class InvalidTicketError < StandardError; end
    class ClosedTicketError < StandardError; end

    VALID_PRIORITIES = %w[low normal high urgent].freeze
    VALID_STATUSES = %w[open pending resolved closed].freeze

    def self.list(store_id:, status: nil)
      require_context_and_read!
      store = Store.find(store_id)
      scope = visible_scope.where(store_id: store.id)
      scope = scope.where(status: normalize_status!(status)) if status.present?
      scope.order(last_message_at: :desc, id: :desc).limit(100)
    end

    def self.read(store_id:, ticket_id:)
      require_context_and_read!
      store = Store.find(store_id)
      visible_scope.where(store_id: store.id).find(ticket_id)
    end

    def self.create(store_id:, subject:, body:, priority: "normal", attachment_ids: [])
      require_context!
      TenantPermission.require!(Current.membership, "support.create")
      store = Store.find(store_id)
      normalized_subject = normalize_subject!(subject)
      normalized_body = normalize_body!(body)
      normalized_priority = normalize_priority!(priority)
      ticket = nil

      ApplicationRecord.transaction(requires_new: true) do
        now = Time.current
        ticket = SupportTicket.create!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          created_by_user_id: Current.user.id,
          ticket_number: "SUP-#{SecureRandom.hex(6).upcase}",
          subject: normalized_subject,
          priority: normalized_priority,
          status: "open",
          source: "in_app",
          last_message_at: now
        )
        message = SupportMessage.create!(
          tenant_id: Current.tenant_id,
          store_id: store.id,
          support_ticket_id: ticket.id,
          author_type: "merchant",
          author_user_id: Current.user.id,
          body: normalized_body
        )
        attach_ready!(ticket: ticket, message: message, attachment_ids: attachment_ids)
      end

      ticket
    end

    def self.reply(store_id:, ticket_id:, body:, attachment_ids: [])
      ticket = read(store_id: store_id, ticket_id: ticket_id)
      raise ClosedTicketError, "closed support tickets cannot receive replies" if ticket.status == "closed"

      message = nil
      ApplicationRecord.transaction(requires_new: true) do
        locked = SupportTicket.lock.find(ticket.id)
        message = SupportMessage.create!(
          tenant_id: Current.tenant_id,
          store_id: locked.store_id,
          support_ticket_id: locked.id,
          author_type: "merchant",
          author_user_id: Current.user.id,
          body: normalize_body!(body)
        )
        attach_ready!(ticket: locked, message: message, attachment_ids: attachment_ids)
        locked.update!(status: "open", last_message_at: message.created_at, resolved_at: nil)
      end
      message
    end

    def self.transition(store_id:, ticket_id:, status:)
      require_context!
      TenantPermission.require!(Current.membership, "support.manage")
      ticket = SupportTicket.where(store_id: Store.find(store_id).id).find(ticket_id)
      normalized_status = normalize_status!(status)
      ticket.update!(
        status: normalized_status,
        resolved_at: %w[resolved closed].include?(normalized_status) ? Time.current : nil
      )
      ticket
    end

    def self.visible_scope
      scope = SupportTicket.all
      return scope if TenantPermission.allowed?(Current.membership, "support.manage")

      scope.where(created_by_user_id: Current.user.id)
    end
    private_class_method :visible_scope

    def self.attach_ready!(ticket:, message:, attachment_ids:)
      ids = Array(attachment_ids).map(&:to_s).reject(&:blank?).uniq
      return if ids.empty?
      raise InvalidTicketError, "too many support attachments" if ids.length > 10

      attachments = SupportAttachment.ready.where(
        id: ids,
        support_ticket_id: ticket.id,
        store_id: ticket.store_id,
        created_by_user_id: Current.user.id,
        support_message_id: nil
      )
      raise InvalidTicketError, "one or more support attachments are invalid" unless attachments.length == ids.length

      attachments.update_all(support_message_id: message.id, updated_at: Time.current)
    end
    private_class_method :attach_ready!

    def self.require_context_and_read!
      require_context!
      TenantPermission.require!(Current.membership, "support.read")
    end
    private_class_method :require_context_and_read!

    def self.require_context!
      raise MissingTenantContextError, "tenant context is required" if Current.tenant_id.blank? || Current.user.blank?
    end
    private_class_method :require_context!

    def self.normalize_subject!(value)
      subject = value.to_s.strip
      raise InvalidTicketError, "subject must be between 3 and 160 characters" unless subject.length.between?(3, 160)

      subject
    end
    private_class_method :normalize_subject!

    def self.normalize_body!(value)
      body = value.to_s.strip
      raise InvalidTicketError, "message must be between 1 and 5000 characters" unless body.length.between?(1, 5_000)

      body
    end
    private_class_method :normalize_body!

    def self.normalize_priority!(value)
      priority = value.to_s
      raise InvalidTicketError, "support ticket priority is invalid" unless VALID_PRIORITIES.include?(priority)

      priority
    end
    private_class_method :normalize_priority!

    def self.normalize_status!(value)
      status = value.to_s
      raise InvalidTicketError, "support ticket status is invalid" unless VALID_STATUSES.include?(status)

      status
    end
    private_class_method :normalize_status!
  end
end
