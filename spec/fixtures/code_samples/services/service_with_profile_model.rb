class ProfileFetcher
  # Uses ActiveRecord on the Profile model. Must NOT be flagged as file-system.
  def call
    Profile.find_by(slug: "x")
  end
end
