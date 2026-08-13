class CreateControlPlaneFoundation < ActiveRecord::Migration[8.0]
  CONTROL_TABLES = %w[
    control_plane_users
    control_plane_sessions
    control_plane_audit_events
  ].freeze

  def up
    ensure_control_plane_role!
    create_control_plane_users
    create_control_plane_sessions
    create_control_plane_audit_events
    configure_runtime_detection
    configure_audit_immutability
    configure_database_access
  end

  def down
    execute "DROP TRIGGER IF EXISTS control_plane_audit_events_append_only ON control_plane_audit_events"
    execute "DROP FUNCTION IF EXISTS crystell.prevent_control_plane_audit_mutation()"
    execute "DROP FUNCTION IF EXISTS crystell.current_role_is_control_plane_runtime()"

    drop_table :control_plane_audit_events
    drop_table :control_plane_sessions
    drop_table :control_plane_users
  end

  private

  def ensure_control_plane_role!
    exists = select_value("SELECT 1 FROM pg_roles WHERE rolname = 'crystell_control_plane_runtime'")
    return if exists

    raise "crystell_control_plane_runtime database role must be provisioned before migrations"
  end

  def create_control_plane_users
    create_table :control_plane_users, id: :uuid do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :status, null: false, default: "active"
      t.string :role, null: false, default: "viewer"
      t.text :mfa_secret_ciphertext
      t.datetime :mfa_enabled_at
      t.integer :failed_login_attempts, null: false, default: 0
      t.datetime :locked_until
      t.datetime :last_authenticated_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :control_plane_users, "lower(email)", unique: true, name: "idx_control_plane_users_email"
    add_check_constraint :control_plane_users,
                         "status IN ('active', 'suspended')",
                         name: "control_plane_users_status_check"
    add_check_constraint :control_plane_users,
                         "role IN ('viewer', 'operator', 'admin', 'owner')",
                         name: "control_plane_users_role_check"
    add_check_constraint :control_plane_users,
                         "failed_login_attempts >= 0",
                         name: "control_plane_users_failed_attempts_check"
  end

  def create_control_plane_sessions
    create_table :control_plane_sessions, id: :uuid do |t|
      t.uuid :control_plane_user_id, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :mfa_verified_at
      t.datetime :privilege_elevated_until
      t.string :ip_hash
      t.text :user_agent
      t.datetime :last_seen_at
      t.timestamps
    end

    add_foreign_key :control_plane_sessions, :control_plane_users
    add_index :control_plane_sessions, :token_digest, unique: true
    add_index :control_plane_sessions,
              [:control_plane_user_id, :expires_at],
              name: "idx_control_plane_sessions_user_expiry"
    add_check_constraint :control_plane_sessions,
                         "expires_at > created_at",
                         name: "control_plane_sessions_expiry_check"
  end

  def create_control_plane_audit_events
    create_table :control_plane_audit_events, id: :uuid do |t|
      t.uuid :control_plane_user_id
      t.uuid :control_plane_session_id
      t.string :action, null: false
      t.string :target_type
      t.string :target_id
      t.string :request_id
      t.string :ip_hash
      t.text :reason
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_foreign_key :control_plane_audit_events, :control_plane_users
    add_foreign_key :control_plane_audit_events, :control_plane_sessions
    add_index :control_plane_audit_events,
              [:control_plane_user_id, :occurred_at],
              name: "idx_control_plane_audit_actor_timeline"
    add_index :control_plane_audit_events,
              [:target_type, :target_id, :occurred_at],
              name: "idx_control_plane_audit_target_timeline"
    add_check_constraint :control_plane_audit_events,
                         "char_length(action) BETWEEN 3 AND 120",
                         name: "control_plane_audit_action_check"
  end

  def configure_runtime_detection
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.current_role_is_control_plane_runtime()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      AS $$
        SELECT EXISTS (
          SELECT 1
          FROM pg_auth_members membership
          JOIN pg_roles role ON role.oid = membership.roleid
          JOIN pg_roles member ON member.oid = membership.member
          WHERE role.rolname = 'crystell_control_plane_runtime'
            AND member.rolname = current_user
        )
      $$
    SQL
  end

  def configure_audit_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_control_plane_audit_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_control_plane_runtime() THEN
          RAISE EXCEPTION 'control_plane_audit_events_are_append_only';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL

    execute <<~SQL
      CREATE TRIGGER control_plane_audit_events_append_only
      BEFORE UPDATE OR DELETE ON control_plane_audit_events
      FOR EACH ROW EXECUTE FUNCTION crystell.prevent_control_plane_audit_mutation()
    SQL
  end

  def configure_database_access
    CONTROL_TABLES.each do |table|
      execute "REVOKE ALL ON #{table} FROM crystell_runtime"
    end

    execute "GRANT SELECT, INSERT, UPDATE ON control_plane_users TO crystell_control_plane_runtime"
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON control_plane_sessions TO crystell_control_plane_runtime"
    execute "GRANT SELECT, INSERT ON control_plane_audit_events TO crystell_control_plane_runtime"
  end
end
