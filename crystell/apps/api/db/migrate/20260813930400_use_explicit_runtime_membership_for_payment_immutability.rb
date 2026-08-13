class UseExplicitRuntimeMembershipForPaymentImmutability < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_payment_transaction_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF crystell.current_role_is_runtime() THEN
          RAISE EXCEPTION 'payment_transactions_are_append_only';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crystell.prevent_payment_transaction_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF pg_has_role(current_user, 'crystell_runtime', 'MEMBER') THEN
          RAISE EXCEPTION 'payment_transactions_are_append_only';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$
    SQL
  end
end
