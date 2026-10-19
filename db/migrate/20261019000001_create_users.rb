class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    # Emails are normalized to lowercase in the model; the unique index is the
    # source of truth if two sign-ups race each other.
    add_index :users, :email, unique: true
    add_check_constraint :users, "role IN ('member', 'admin')", name: "users_role_allowed"
  end
end
