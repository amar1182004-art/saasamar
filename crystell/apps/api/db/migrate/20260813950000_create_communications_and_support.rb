class CreateCommunicationsAndSupport < ActiveRecord::Migration[8.0]
  TENANT_TABLES = %w[
    support_tickets
    support_messages
    support_attachments
    communication_provider_accounts
    notification_templates
    notification_deliveries
    notifications
  ].freeze

  def up
    create_support_tables
    create_communications_tables
    add_scope_foreign_keys
    configure_runtime_access
    configure_rls
    configure_immutability
    configure_control_plane_capabilities
  end

  def down
    drop_control_plane_capabilities
    execute "DROP TRIGGER IF EXISTS support_messages_append_only ON support_messages"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_support_message_mutation()"

    TENANT_TABLES.reverse_each do |table|
      execute "DROP POLICY IF EXISTS tenant_runtime_isolation ON #{table}"
      execute "DROP POLICY IF EXISTS migration_admin_access ON #{table}"
      drop_table table
    end
  end

  private

  def create_support_tables
    create_table :support_tickets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :created_by_user_id, null: false
      t.uuid :assigned_control_plane_user_id
      t.string :ticket_number, null: false
      t.string :subject, null: false
      t.string :priority, null: false, default: "normal"
      t.string :status, null: false, default: "open"
      t.string :source, null: false, default: "in_app"
      t.datetime :last_message_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :resolved_at
      t.integer :lock_version, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :support_tickets, :tenants
    add_foreign_key :support_tickets, :users, column: :created_by_user_id
    add_index :support_tickets, [:tenant_id, :ticket_number], unique: true, name: "idx_support_tickets_number"
    add_index :support_tickets, [:id, :tenant_id, :store_id], unique: true, name: "idx_support_tickets_id_tenant_store"
    add_index :support_tickets, [:tenant_id, :store_id, :status, :last_message_at], name: "idx_support_tickets_queue"
    add_check_constraint :support_tickets, "priority IN ('low', 'normal', 'high', 'urgent')", name: "support_tickets_priority_check"
    add_check_constraint :support_tickets, "status IN ('open', 'pending', 'resolved', 'closed')", name: "support_tickets_status_check"
    add_check_constraint :support_tickets, "source IN ('in_app', 'email', 'sms', 'whatsapp')", name: "support_tickets_source_check"

    create_table :support_messages, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :support_ticket_id, null: false
      t.string :author_type, null: false
      t.uuid :author_user_id
      t.uuid :author_control_plane_user_id
      t.text :body, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :support_messages, :tenants
    add_foreign_key :support_messages, :users, column: :author_user_id
    add_index :support_messages, [:id, :tenant_id, :store_id], unique: true, name: "idx_support_messages_id_tenant_store"
    add_index :support_messages, [:tenant_id, :store_id, :support_ticket_id, :created_at], name: "idx_support_messages_thread"
    add_check_constraint :support_messages, "author_type IN ('merchant', 'support', 'system')", name: "support_messages_author_type_check"
    add_check_constraint :support_messages,
                         "(author_type = 'merchant' AND author_user_id IS NOT NULL AND author_control_plane_user_id IS NULL) OR (author_type = 'support' AND author_user_id IS NULL AND author_control_plane_user_id IS NOT NULL) OR (author_type = 'system' AND author_user_id IS NULL AND author_control_plane_user_id IS NULL)",
                         name: "support_messages_author_identity_check"

    create_table :support_attachments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :support_ticket_id, null: false
      t.uuid :support_message_id
      t.uuid :created_by_user_id
      t.uuid :created_by_control_plane_user_id
      t.string :kind, null: false
      t.string :object_key, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :checksum_sha256
      t.string :status, null: false, default: "pending"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :support_attachments, :tenants
    add_foreign_key :support_attachments, :users, column: :created_by_user_id
    add_index :support_attachments, [:id, :tenant_id, :store_id], unique: true, name: "idx_support_attachments_id_tenant_store"
    add_index :support_attachments, [:tenant_id, :object_key], unique: true, name: "idx_support_attachments_object_key"
    add_index :support_attachments, [:tenant_id, :store_id, :support_ticket_id, :created_at], name: "idx_support_attachments_ticket"
    add_check_constraint :support_attachments, "kind IN ('file', 'image', 'video')", name: "support_attachments_kind_check"
    add_check_constraint :support_attachments, "status IN ('pending', 'ready', 'failed')", name: "support_attachments_status_check"
    add_check_constraint :support_attachments, "byte_size > 0", name: "support_attachments_byte_size_check"
    add_check_constraint :support_attachments,
                         "created_by_user_id IS NOT NULL OR created_by_control_plane_user_id IS NOT NULL",
                         name: "support_attachments_creator_check"
  end

  def create_communications_tables
    create_table :communication_provider_accounts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :channel, null: false
      t.string :provider_key, null: false
      t.string :mode, null: false, default: "test"
      t.string :status, null: false, default: "active"
      t.string :display_name
      t.text :credentials_ciphertext, null: false
      t.jsonb :public_config, null: false, default: {}
      t.datetime :last_verified_at
      t.timestamps
    end

    add_foreign_key :communication_provider_accounts, :tenants
    add_index :communication_provider_accounts,
              [:tenant_id, :store_id, :channel, :provider_key, :mode],
              unique: true,
              name: "idx_communication_accounts_provider"
    add_index :communication_provider_accounts, [:id, :tenant_id, :store_id], unique: true, name: "idx_communication_accounts_scope"
    add_check_constraint :communication_provider_accounts, "channel IN ('email', 'sms', 'whatsapp')", name: "communication_accounts_channel_check"
    add_check_constraint :communication_provider_accounts, "mode IN ('test', 'live')", name: "communication_accounts_mode_check"
    add_check_constraint :communication_provider_accounts, "status IN ('active', 'disabled')", name: "communication_accounts_status_check"

    create_table :notification_templates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.string :key, null: false
      t.string :channel, null: false
      t.string :locale, null: false, default: "ar"
      t.string :subject
      t.text :body, null: false
      t.string :status, null: false, default: "draft"
      t.jsonb :variables, null: false, default: []
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_foreign_key :notification_templates, :tenants
    add_index :notification_templates,
              [:tenant_id, :store_id, :key, :channel, :locale],
              unique: true,
              name: "idx_notification_templates_identity"
    add_index :notification_templates, [:id, :tenant_id, :store_id], unique: true, name: "idx_notification_templates_scope"
    add_check_constraint :notification_templates, "channel IN ('email', 'sms', 'whatsapp')", name: "notification_templates_channel_check"
    add_check_constraint :notification_templates, "status IN ('draft', 'active', 'archived')", name: "notification_templates_status_check"

    create_table :notification_deliveries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id, null: false
      t.uuid :notification_template_id, null: false
      t.uuid :communication_provider_account_id, null: false
      t.uuid :user_id
      t.string :channel, null: false
      t.text :recipient_ciphertext, null: false
      t.string :destination_fingerprint, null: false
      t.text :payload_ciphertext, null: false
      t.string :status, null: false, default: "queued"
      t.string :idempotency_key, null: false
      t.string :provider_message_id
      t.integer :attempts, null: false, default: 0
      t.datetime :scheduled_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :sent_at
      t.datetime :failed_at
      t.text :last_error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :notification_deliveries, :tenants
    add_foreign_key :notification_deliveries, :users
    add_index :notification_deliveries,
              [:tenant_id, :store_id, :idempotency_key],
              unique: true,
              name: "idx_notification_deliveries_idempotency"
    add_index :notification_deliveries, [:id, :tenant_id, :store_id], unique: true, name: "idx_notification_deliveries_scope"
    add_index :notification_deliveries, [:tenant_id, :status, :scheduled_at], name: "idx_notification_deliveries_queue"
    add_check_constraint :notification_deliveries, "channel IN ('email', 'sms', 'whatsapp')", name: "notification_deliveries_channel_check"
    add_check_constraint :notification_deliveries, "status IN ('queued', 'sending', 'sent', 'failed')", name: "notification_deliveries_status_check"
    add_check_constraint :notification_deliveries, "attempts >= 0", name: "notification_deliveries_attempts_check"

    create_table :notifications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :store_id
      t.uuid :user_id, null: false
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :action_url
      t.datetime :read_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_foreign_key :notifications, :tenants
    add_foreign_key :notifications, :users
    add_index :notifications, [:id, :tenant_id], unique: true, name: "idx_notifications_id_tenant"
    add_index :notifications, [:tenant_id, :user_id, :read_at, :created_at], name: "idx_notifications_inbox"
  end

  def add_scope_foreign_keys
    execute "ALTER TABLE support_tickets ADD CONSTRAINT support_tickets_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE support_messages ADD CONSTRAINT support_messages_ticket_scope_fk FOREIGN KEY (support_ticket_id, tenant_id, store_id) REFERENCES support_tickets(id, tenant_id, store_id)"
    execute "ALTER TABLE support_attachments ADD CONSTRAINT support_attachments_ticket_scope_fk FOREIGN KEY (support_ticket_id, tenant_id, store_id) REFERENCES support_tickets(id, tenant_id, store_id)"
    execute "ALTER TABLE support_attachments ADD CONSTRAINT support_attachments_message_scope_fk FOREIGN KEY (support_message_id, tenant_id, store_id) REFERENCES support_messages(id, tenant_id, store_id)"
    execute "ALTER TABLE communication_provider_accounts ADD CONSTRAINT communication_accounts_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE notification_templates ADD CONSTRAINT notification_templates_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE notification_deliveries ADD CONSTRAINT notification_deliveries_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
    execute "ALTER TABLE notification_deliveries ADD CONSTRAINT notification_deliveries_template_scope_fk FOREIGN KEY (notification_template_id, tenant_id, store_id) REFERENCES notification_templates(id, tenant_id, store_id)"
    execute "ALTER TABLE notification_deliveries ADD CONSTRAINT notification_deliveries_account_scope_fk FOREIGN KEY (communication_provider_account_id, tenant_id, store_id) REFERENCES communication_provider_accounts(id, tenant_id, store_id)"
    execute "ALTER TABLE notifications ADD CONSTRAINT notifications_store_scope_fk FOREIGN KEY (store_id, tenant_id) REFERENCES stores(id, tenant_id)"
  end

  def configure_runtime_access
    execute "GRANT SELECT, INSERT, UPDATE ON support_tickets TO crystell_runtime"
    execute "GRANT SELECT, INSERT ON support_messages TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON support_attachments TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON communication_provider_accounts TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON notification_templates TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON notification_deliveries TO crystell_runtime"
    execute "GRANT SELECT, INSERT, UPDATE ON notifications TO crystell_runtime"
  end

  def configure_rls
    TENANT_TABLES.each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
      execute <<~SQL
        CREATE POLICY tenant_runtime_isolation ON #{table}
        FOR ALL
        TO crystell_runtime
        USING (tenant_id = crystell.current_tenant_id())
        WITH CHECK (tenant_id = crystell.current_tenant_id())
      SQL
      execute <<~SQL
        DO $$
        BEGIN
          EXECUTE format(
            'CREATE POLICY migration_admin_access ON #{table} FOR ALL TO %I USING (true) WITH CHECK (true)',
            current_user
          );
        END
        $$
      SQL
    end
  end

  def configure_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_support_message_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() THEN
          RAISE EXCEPTION 'support_messages_are_append_only';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;
        RETURN NEW;
      END
      $$
    SQL
    execute <<~SQL
      CREATE TRIGGER support_messages_append_only
      BEFORE UPDATE OR DELETE ON support_messages
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_support_message_mutation()
    SQL
  end

  def configure_control_plane_capabilities
    execute <<~SQL
      CREATE OR REPLACE FUNCTION control_plane_api.support_ticket_directory(
        p_status text,
        p_query text,
        p_limit integer,
        p_offset integer,
        p_actor_id uuid
      )
      RETURNS TABLE(
        ticket_id uuid,
        tenant_id uuid,
        tenant_name text,
        store_id uuid,
        store_name text,
        ticket_number text,
        subject text,
        priority text,
        ticket_status text,
        source text,
        last_message_at timestamp without time zone,
        created_at timestamp without time zone
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
        SELECT ticket.id,
               ticket.tenant_id,
               tenant.name::text,
               ticket.store_id,
               store.name::text,
               ticket.ticket_number::text,
               ticket.subject::text,
               ticket.priority::text,
               ticket.status::text,
               ticket.source::text,
               ticket.last_message_at,
               ticket.created_at
        FROM support_tickets ticket
        JOIN tenants tenant ON tenant.id = ticket.tenant_id
        JOIN stores store ON store.id = ticket.store_id AND store.tenant_id = ticket.tenant_id
        WHERE (NULLIF(BTRIM(p_status), '') IS NULL OR ticket.status = BTRIM(p_status))
          AND EXISTS (
            SELECT 1 FROM control_plane_users actor
            WHERE actor.id = p_actor_id
              AND actor.status = 'active'
              AND actor.role IN ('viewer', 'operator', 'admin', 'owner')
          )
          AND (
            NULLIF(BTRIM(p_query), '') IS NULL
            OR ticket.ticket_number ILIKE '%' || BTRIM(p_query) || '%'
            OR ticket.subject ILIKE '%' || BTRIM(p_query) || '%'
            OR tenant.name ILIKE '%' || BTRIM(p_query) || '%'
          )
        ORDER BY ticket.last_message_at DESC, ticket.id
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100)
        OFFSET GREATEST(COALESCE(p_offset, 0), 0)
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION control_plane_api.support_ticket_thread(p_ticket_id uuid, p_actor_id uuid)
      RETURNS TABLE(
        ticket_id uuid,
        tenant_id uuid,
        tenant_name text,
        store_id uuid,
        store_name text,
        ticket_number text,
        subject text,
        priority text,
        ticket_status text,
        source text,
        last_message_at timestamp without time zone,
        created_at timestamp without time zone,
        message_id uuid,
        author_type text,
        author_label text,
        message_body text,
        message_created_at timestamp without time zone,
        message_attachments jsonb
      )
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
        SELECT ticket.id,
               ticket.tenant_id,
               tenant.name::text,
               ticket.store_id,
               store.name::text,
               ticket.ticket_number::text,
               ticket.subject::text,
               ticket.priority::text,
               ticket.status::text,
               ticket.source::text,
               ticket.last_message_at,
               ticket.created_at,
               message.id,
               message.author_type::text,
               CASE
                 WHEN message.author_type = 'merchant' THEN merchant.email::text
                 WHEN message.author_type = 'support' THEN support_user.email::text
                 ELSE 'Crystell'
               END,
               message.body,
               message.created_at,
               COALESCE(
                 (
                   SELECT jsonb_agg(
                     jsonb_build_object(
                       'id', attachment.id,
                       'kind', attachment.kind,
                       'filename', attachment.filename,
                       'content_type', attachment.content_type,
                       'byte_size', attachment.byte_size
                     ) ORDER BY attachment.created_at, attachment.id
                   )
                   FROM support_attachments attachment
                   WHERE attachment.support_message_id = message.id
                     AND attachment.status = 'ready'
                 ),
                 '[]'::jsonb
               )
        FROM support_tickets ticket
        JOIN tenants tenant ON tenant.id = ticket.tenant_id
        JOIN stores store ON store.id = ticket.store_id AND store.tenant_id = ticket.tenant_id
        LEFT JOIN support_messages message ON message.support_ticket_id = ticket.id
        LEFT JOIN users merchant ON merchant.id = message.author_user_id
        LEFT JOIN control_plane_users support_user ON support_user.id = message.author_control_plane_user_id
        WHERE ticket.id = p_ticket_id
          AND EXISTS (
            SELECT 1 FROM control_plane_users actor
            WHERE actor.id = p_actor_id
              AND actor.status = 'active'
              AND actor.role IN ('viewer', 'operator', 'admin', 'owner')
          )
        ORDER BY message.created_at ASC, message.id ASC
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION control_plane_api.support_attachment(
        p_ticket_id uuid,
        p_attachment_id uuid,
        p_actor_id uuid
      )
      RETURNS TABLE(
        object_key text,
        filename text,
        content_type text,
        byte_size bigint
      )
      LANGUAGE plpgsql
      STABLE
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM control_plane_users
          WHERE id = p_actor_id AND status = 'active' AND role IN ('viewer', 'operator', 'admin', 'owner')
        ) THEN
          RAISE EXCEPTION 'support_actor_forbidden';
        END IF;

        RETURN QUERY
          SELECT attachment.object_key::text,
                 attachment.filename::text,
                 attachment.content_type::text,
                 attachment.byte_size
          FROM support_attachments attachment
          WHERE attachment.support_ticket_id = p_ticket_id
            AND attachment.id = p_attachment_id
            AND attachment.status = 'ready';
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION control_plane_api.append_support_reply(
        p_ticket_id uuid,
        p_actor_id uuid,
        p_body text
      )
      RETURNS uuid
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
      DECLARE
        ticket support_tickets%ROWTYPE;
        message_id uuid := gen_random_uuid();
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM control_plane_users
          WHERE id = p_actor_id AND status = 'active' AND role IN ('operator', 'admin', 'owner')
        ) THEN
          RAISE EXCEPTION 'support_actor_forbidden';
        END IF;

        IF char_length(BTRIM(COALESCE(p_body, ''))) NOT BETWEEN 1 AND 5000 THEN
          RAISE EXCEPTION 'support_message_invalid';
        END IF;

        SELECT * INTO ticket FROM support_tickets WHERE id = p_ticket_id FOR UPDATE;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'support_ticket_not_found';
        END IF;
        IF ticket.status = 'closed' THEN
          RAISE EXCEPTION 'support_ticket_closed';
        END IF;

        INSERT INTO support_messages(
          id, tenant_id, store_id, support_ticket_id, author_type,
          author_control_plane_user_id, body, metadata, created_at, updated_at
        ) VALUES (
          message_id, ticket.tenant_id, ticket.store_id, ticket.id, 'support',
          p_actor_id, BTRIM(p_body), '{}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        );

        UPDATE support_tickets
        SET status = 'pending', last_message_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
        WHERE id = ticket.id;

        RETURN message_id;
      END
      $$
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION control_plane_api.transition_support_ticket(
        p_ticket_id uuid,
        p_actor_id uuid,
        p_status text
      )
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM control_plane_users
          WHERE id = p_actor_id AND status = 'active' AND role IN ('operator', 'admin', 'owner')
        ) THEN
          RAISE EXCEPTION 'support_actor_forbidden';
        END IF;
        IF p_status NOT IN ('open', 'pending', 'resolved', 'closed') THEN
          RAISE EXCEPTION 'support_status_invalid';
        END IF;

        UPDATE support_tickets
        SET status = p_status,
            resolved_at = CASE WHEN p_status IN ('resolved', 'closed') THEN CURRENT_TIMESTAMP ELSE NULL END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = p_ticket_id;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'support_ticket_not_found';
        END IF;
      END
      $$
    SQL

    execute "REVOKE ALL ON FUNCTION control_plane_api.support_ticket_directory(text, text, integer, integer, uuid) FROM PUBLIC"
    execute "REVOKE ALL ON FUNCTION control_plane_api.support_ticket_thread(uuid, uuid) FROM PUBLIC"
    execute "REVOKE ALL ON FUNCTION control_plane_api.support_attachment(uuid, uuid, uuid) FROM PUBLIC"
    execute "REVOKE ALL ON FUNCTION control_plane_api.append_support_reply(uuid, uuid, text) FROM PUBLIC"
    execute "REVOKE ALL ON FUNCTION control_plane_api.transition_support_ticket(uuid, uuid, text) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION control_plane_api.support_ticket_directory(text, text, integer, integer, uuid) TO crystell_control_plane_runtime"
    execute "GRANT EXECUTE ON FUNCTION control_plane_api.support_ticket_thread(uuid, uuid) TO crystell_control_plane_runtime"
    execute "GRANT EXECUTE ON FUNCTION control_plane_api.support_attachment(uuid, uuid, uuid) TO crystell_control_plane_runtime"
    execute "GRANT EXECUTE ON FUNCTION control_plane_api.append_support_reply(uuid, uuid, text) TO crystell_control_plane_runtime"
    execute "GRANT EXECUTE ON FUNCTION control_plane_api.transition_support_ticket(uuid, uuid, text) TO crystell_control_plane_runtime"
  end

  def drop_control_plane_capabilities
    execute "DROP FUNCTION IF EXISTS control_plane_api.transition_support_ticket(uuid, uuid, text)"
    execute "DROP FUNCTION IF EXISTS control_plane_api.append_support_reply(uuid, uuid, text)"
    execute "DROP FUNCTION IF EXISTS control_plane_api.support_attachment(uuid, uuid, uuid)"
    execute "DROP FUNCTION IF EXISTS control_plane_api.support_ticket_thread(uuid, uuid)"
    execute "DROP FUNCTION IF EXISTS control_plane_api.support_ticket_directory(text, text, integer, integer, uuid)"
  end
end
