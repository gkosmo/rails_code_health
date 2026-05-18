class FixUserEmails < ActiveRecord::Migration[7.0]
  def up
    ActiveRecord::Base.connection.execute("UPDATE users SET email = LOWER(email)")
  end
end
