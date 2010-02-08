# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base
  helper :all # include all helpers, all the time

  # See ActionController::RequestForgeryProtection for details
  # Uncomment the :secret if you're not using the cookie session store
  protect_from_forgery # :secret => '8406dc20b6131ea8a90ec68109f869b1'
  
  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  # filter_parameter_logging :password
  
  # before_filter :get_tag_cloud
  before_filter :check_current_eycp
  filter_parameter_logging :password, :password_confirmation
  helper_method :current_user_session, :current_user, :has_eycp?

  # 访问了acl9控制的资源而没有权限时引发这个异常，在此捕获处理
  rescue_from 'Acl9::AccessDenied', :with => :access_denied
  rescue_from 'ActiveRecord::RecordNotFound',:with => :record_not_found
  rescue_from 'ActionController::MethodNotAllowed',:with => :record_not_found

private

  # def get_tag_cloud
  #   @tag_cloud = Video.tag_counts
  # end

  # 如果其它地方删了eycp这个cookie，只能在openid里重新登陆才能生成这个cookie,
  # 所以openid只从enjoyoung cookie passport验证登陆状态登陆
  def check_current_eycp
    if has_eycp?
      @current_user = login_from_enjoyoung_cookie_passport unless current_user
    end
  end

  def has_eycp?
    !cookies[:eycp].blank?
  end

  def current_user_session
    return @current_user_session if defined?(@current_user_session)
    @current_user_session = UserSession.find
  end

  def current_user
     return @current_user if defined?(@current_user)
     @current_user = current_user_session && current_user_session.user
  end

  # 以eycp cookie通行证信息登陆或注册新用户
  def login_from_enjoyoung_cookie_passport
    if eycp_info = parse_eycp
      begin
      register_new_user(eycp_info) unless @current_user = User.find_by_openid_identifier(eycp_info['openid_identifier'])
      rescue
        render :text => "User lookup or register error!"
      end
      @current_user_session = UserSession.new(@current_user, true)
      @current_user if  @current_user_session.save
    else
      render :text => "Fake eycp!"
    end
  end

  # 解析eycp cookie，得到用户通行证信息
  def parse_eycp
    begin
      eycp_key = OpenSSL::PKey::RSA.new(File.read(RSA_KEY['public_key_path']))
      cookie_passport = eycp_key.public_decrypt(Base64.decode64(cookies[:eycp])) unless cookies[:eycp].blank?
      if cookie_passport && cookie_passport.include?(CONFIG['eycp_root'])
        cp         = cookie_passport.split("\t")
        openid_url = cp[0] # openid
        login      = cp[1] # 登陆账号
        email      = cp[2] # 注册时的邮件
        name       = cp[3] # 标准资料设定里的昵称
        return {'nickname' => login, 'name' => name, 'email' => email, 'openid_identifier' => openid_url}
      else
        return false
      end
    rescue OpenSSL::PKey::RSAError
      return false
    end
  end
  
  # 注册新用户
  def register_new_user(register_info)
    @current_user = User.build_from_openid(register_info)
    return @current_user if @current_user.save 
  end

  def require_user
    unless current_user
      store_location
      flash[:notice] = "You must be logged in to access this page"
      redirect_to new_user_session_url
      return false
    end
  end

  def store_location
    session[:return_to] = request.request_uri
  end

  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end

  # acl9访问控制不通过时
  def access_denied
    if current_user
      render :template => 'shared/access_denied'
    else
      flash[:notice] = '你没有登陆或者没有权限执行此操作。'
      redirect_to login_path
    end
  end

  def record_not_found
    # render :template => 'shared/404'
    flash[:notice] = '没有这个东西'
    redirect_to '/'
  end
	
end
