class User < ApplicationRecord
  # A deliberately fat model: 16+ public methods, >200 code lines.

  has_many :posts
  has_many :comments
  has_many :likes
  has_many :follows
  belongs_to :organization
  has_one :profile

  validates :email, presence: true, uniqueness: true
  validates :username, presence: true, length: { minimum: 3, maximum: 50 }
  validates :first_name, presence: true
  validates :last_name, presence: true

  before_save :normalize_email
  before_create :generate_api_token
  after_commit :send_welcome_email, on: :create

  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: 'admin') }
  scope :recent, -> { order(created_at: :desc).limit(10) }

  def full_name
    "#{first_name} #{last_name}"
  end

  def display_name
    username.present? ? username : full_name
  end

  def admin?
    role == 'admin'
  end

  def moderator?
    role == 'moderator'
  end

  def active?
    active == true
  end

  def deactivate!
    update!(active: false)
    posts.update_all(published: false)
    comments.update_all(hidden: true)
    likes.destroy_all
    follows.destroy_all
    UserMailer.deactivation_email(self).deliver_later
    Rails.cache.delete("user_#{id}_profile")
    Rails.cache.delete("user_#{id}_display")
    Rails.cache.delete("user_#{id}_feed")
    Rails.logger.info("User #{id} deactivated at #{Time.current}")
  end

  def activate!
    update!(active: true)
    posts.update_all(published: true)
    UserMailer.activation_email(self).deliver_later
    Rails.cache.delete("user_#{id}_profile")
    Rails.cache.delete("user_#{id}_display")
    Rails.logger.info("User #{id} activated at #{Time.current}")
  end

  def generate_reset_token
    self.reset_token = SecureRandom.hex(20)
    self.reset_token_expires_at = 24.hours.from_now
    self.reset_requested_at = Time.current
    self.reset_count = (reset_count || 0) + 1
    save!
    UserMailer.password_reset_email(self).deliver_later
    Rails.logger.info("Password reset requested for user #{id}")
    reset_token
  end

  def reset_password!(new_password)
    self.password = new_password
    self.reset_token = nil
    self.reset_token_expires_at = nil
    self.reset_requested_at = nil
    self.password_changed_at = Time.current
    save!
    UserMailer.password_changed_email(self).deliver_later
    Rails.cache.delete("user_#{id}_auth")
    Rails.logger.info("Password changed for user #{id}")
  end

  def posts_count
    posts.published.count
  end

  def recent_activity
    activities = []
    activities += posts.order(created_at: :desc).limit(5).to_a
    activities += comments.order(created_at: :desc).limit(5).to_a
    activities += likes.order(created_at: :desc).limit(5).to_a
    activities += follows.order(created_at: :desc).limit(5).to_a
    activities.sort_by(&:created_at).reverse.first(10)
  end

  def follow!(other_user)
    return if following?(other_user)
    follows.create!(followed_id: other_user.id)
    other_user.increment!(:followers_count)
    self.increment!(:following_count)
    Notification.create!(user: other_user, actor: self, kind: :new_follower)
    Rails.cache.delete("user_#{id}_following")
    Rails.cache.delete("user_#{other_user.id}_followers")
  end

  def unfollow!(other_user)
    return unless following?(other_user)
    follows.find_by!(followed_id: other_user.id).destroy
    other_user.decrement!(:followers_count)
    self.decrement!(:following_count)
    Rails.cache.delete("user_#{id}_following")
    Rails.cache.delete("user_#{other_user.id}_followers")
  end

  def following?(other_user)
    follows.where(followed_id: other_user.id).exists?
  end

  def like!(post)
    return if liked?(post)
    likes.create!(likeable: post)
    post.increment!(:likes_count)
    post.user.increment!(:total_likes_received)
    Notification.create!(user: post.user, actor: self, kind: :post_liked, target: post)
    Rails.cache.delete("post_#{post.id}_likes")
    Rails.cache.delete("user_#{id}_liked_posts")
  end

  def unlike!(post)
    return unless liked?(post)
    likes.find_by!(likeable: post).destroy
    post.decrement!(:likes_count)
    post.user.decrement!(:total_likes_received)
    Rails.cache.delete("post_#{post.id}_likes")
    Rails.cache.delete("user_#{id}_liked_posts")
  end

  def liked?(post)
    likes.where(likeable: post).exists?
  end

  def update_profile!(attrs)
    profile.update!(attrs)
    expire_cache
    Rails.logger.info("Profile updated for user #{id}")
  end

  def send_notification(message, kind: :info)
    Notification.create!(user: self, message: message, kind: kind)
    UserMailer.notification_email(self, message).deliver_later if email_notifications?
    Rails.cache.delete("user_#{id}_notifications")
  end

  def to_api_hash
    {
      id: id,
      username: username,
      full_name: full_name,
      email: email,
      role: role,
      active: active?,
      followers_count: followers_count,
      following_count: following_count,
      posts_count: posts_count,
      created_at: created_at.iso8601,
      updated_at: updated_at.iso8601
    }
  end

  def suspend!(reason:)
    update!(suspended: true, suspended_at: Time.current, suspension_reason: reason)
    posts.update_all(hidden: true)
    UserMailer.suspension_email(self, reason).deliver_later
    AuditLog.create!(user: self, action: :suspended, metadata: { reason: reason })
    Rails.cache.delete("user_#{id}_profile")
    Rails.logger.warn("User #{id} suspended: #{reason}")
  end

  def unsuspend!
    update!(suspended: false, suspended_at: nil, suspension_reason: nil)
    posts.update_all(hidden: false)
    UserMailer.unsuspension_email(self).deliver_later
    AuditLog.create!(user: self, action: :unsuspended)
    Rails.cache.delete("user_#{id}_profile")
    Rails.logger.info("User #{id} unsuspended at #{Time.current}")
  end

  def transfer_to_organization!(new_org)
    old_org = organization
    update!(organization: new_org)
    old_org.decrement!(:members_count)
    new_org.increment!(:members_count)
    AuditLog.create!(user: self, action: :org_transfer, metadata: { from: old_org.id, to: new_org.id })
    Rails.cache.delete("user_#{id}_org")
    Rails.logger.info("User #{id} transferred from org #{old_org.id} to #{new_org.id}")
  end

  private

  def normalize_email
    self.email = email.strip.downcase
    self.email = email.gsub(/\+.*@/, '@') if strip_email_tags?
  end

  def generate_api_token
    self.api_token = SecureRandom.hex(32)
  end

  def send_welcome_email
    UserMailer.welcome_email(self).deliver_later
  end

  def email_notifications?
    preferences.fetch('email_notifications', true)
  end

  def expire_cache
    Rails.cache.delete("user_#{id}_profile")
    Rails.cache.delete("user_#{id}_display")
    Rails.cache.delete("user_#{id}_feed")
    Rails.cache.delete("user_#{id}_auth")
    Rails.cache.delete("user_#{id}_following")
    Rails.cache.delete("user_#{id}_followers")
    Rails.cache.delete("user_#{id}_notifications")
    Rails.cache.delete("user_#{id}_liked_posts")
    Rails.cache.delete("user_#{id}_org")
    Rails.logger.debug("Cache expired for user #{id}")
  end
end
