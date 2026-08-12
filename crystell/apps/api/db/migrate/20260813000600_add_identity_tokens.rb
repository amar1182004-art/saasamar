class AddIdentityTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email_verified_at, :datetime

    create_table :identity_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :purpose, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end

    add_index :identity_tokens, :token_digest, unique: true
    add_index :identity_tokens, %i[user_id purpose consumed_at expires_at], name: "index_identity_tokens_on_user_purpose_state"
    add_check_constraint :identity_tokens,
      "purpose IN ('email_verification','password_reset')",
      name: "identity_tokens_purpose_check"
  end
end
