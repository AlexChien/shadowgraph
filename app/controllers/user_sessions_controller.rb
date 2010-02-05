# app/controllers/user_sessions_controller.rb
class UserSessionsController < ApplicationController

  before_filter :require_user, :only => :destroy

  protect_from_forgery :except => [:create] # since openid doesn't pass auth token
  skip_before_filter :current_user, :only => :create

  def new
    @user_session = UserSession.new
  end

  # def create
  #   @user_session = UserSession.new(params[:user_session])
  #   if @user_session.save
  #     flash[:notice] = t("login_successful")
  #     redirect_back_or_default account_url
  #   else
  #     render :action => :new
  #   end
  # end
  
  # def destroy
  #   current_user_session.destroy
  #   flash[:notice] = t("logout_successful")
  #   redirect_back_or_default new_user_session_url
  # end  
  
  def create
    if using_open_id?
      open_id_authentication
    else
      # password_authentication #原始密码登陆
      redirect_to :action => 'new'
    end    
  end
  
  def destroy
    current_user_session.destroy
    cookies.delete :eycp, :domain => EYCP_DOMAIN    
    flash[:notice] = t("logout_successful")
    redirect_back_or_default new_user_session_url
  end  
  
private

  def password_authentication
    @user_session = UserSession.new(params[:user_session])
    success = @user_session.save
    respond_to do |format|
      format.html do
        if success
          flash[:notice] = t("login_successful")
          redirect_back_or_default products_path
        else
          flash.now[:error] = t("login_failed")
          render :new
        end
      end
      format.js do
        user = success ? @user_session.record : nil
        render :json => user ? {:ship_address => user.ship_address, :bill_address => user.bill_address}.to_json : success.to_json
      end
    end     
  end

  def open_id_authentication
    authenticate_with_open_id(params[:openid_identifier], 
                              :required => [:nickname, :email], 
                              :optional => [:fullname, :gender]
                              ) do |result, openid_identifier, registration|
      if result.successful?
        if user = User.find_by_openid_identifier(openid_identifier)
          # debugger
          @current_user_session = UserSession.new(user, true) #用authlogic维护session
          @current_user_session.save
          flash[:notice] = t("login_successful")
          redirect_back_or_default videos_path
        else
          # debugger
          user = User.build_from_openid(registration.merge('openid_identifier' => openid_identifier))
          if user.save
            @current_user_session = UserSession.new(user, true) #用authlogic维护session
            @current_user_session.save
            flash[:notice] = t("signe_up_successful")
            redirect_back_or_default videos_path
          else
            session[:openid_attributes] = user.attributes
            flash[:notice] = "It looks like you don't have an account yet, please create one below."
            redirect_to CONFIG['eycp_register']
          end
        end
      else
        flash.now[:error] = result.message
        render :action => 'new'
      end
    end
  end

end