class AddAppendOnlySecurityEvents < ActiveRecord::Migration[8.0]
  def up
    create_table :security_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :actor_user_id
      t.uuid :tenant_id
      t.string :event_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_index :security_events, %i[actor_user_id occurred_at], name: "index_security_events_on_actor_and_time"
    add_index :security_events, %i[tenant_id occurred_at], name: "index_security_events_on_tenant_and_time"
    add_index :security_events, %i[event_type occurred_at], name: "index_security_events_on_type_and_time"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.append_current_security_event(
        p_event_type text,
        p_metadata jsonb DEFAULT '{}'::jsonb
      )
      RETURNS uuid
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = pg_catalog, public, crystell
      AS $$
      DECLARE
        v_event_id uuid := gen_random_uuid();
        v_user_id uuid := crystell.current_user_id();
        v_tenant_id uuid := crystell.current_tenant_id();
      BEGIN
        IF v_user_id IS NULL THEN
          RAISE EXCEPTION 'authenticated user context is required';
        END IF;

        IF p_event_type IS NULL OR length(p_event_type) < 3 OR length(p_event_type) > 100 THEN
          RAISE EXCEPTION 'invalid security event type';
        END IF;

        INSERT INTO public.security_events (
          id, actor_user_id, tenant_id, event_type, metadata, occurred_at, created_at, updated_at
        ) VALUES (
          v_event_id,
          v_user_id,
          v_tenant_id,
          p_event_type,
          COALESCE(p_metadata, '{}'::jsonb),
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        );

        RETURN v_event_id;
      END
      $$
    SQL

    execute "REVOKE ALL ON TABLE security_events FROM crystell_runtime"
    execute "REVOKE ALL ON FUNCTION crystell.append_current_security_event(text,jsonb) FROM PUBLIC"
    execute "GRANT EXECUTE ON FUNCTION crystell.append_current_security_event(text,jsonb) TO crystell_runtime"
  end

  def down
    execute "DROP FUNCTION IF EXISTS crystell.append_current_security_event(text,jsonb)"
    drop_table :security_events
  end
end
