class UsersController < ApplicationController
  def show
    @user = current_user_record
  end

  private

  def current_user_record
    # Acceptable: model access lives in a private helper, not in the action.
    User.find(session[:user_id])
  end
end
