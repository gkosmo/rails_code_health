class BackfillUserEmails < ActiveRecord::Migration[7.0]
  def up
    User.find_each do |user|
      user.update_columns(email: "#{user.username}@example.com")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
