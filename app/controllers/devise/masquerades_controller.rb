class Devise::MasqueradesController < DeviseController
  Devise.mappings.each do |name, _|
    class_eval <<-METHODS, __FILE__, __LINE__ + 1
      skip_before_action :masquerade_#{name}!, raise: false
    METHODS
  end
  skip_before_action :masquerade!, raise: false

  prepend_before_action :authenticate_scope!, :masquerade_authorize!

  before_action :save_masquerade_owner_session, only: :show

  after_action :cleanup_masquerade_owner_session, only: :back

  def show
    self.resource = find_resource

    unless resource
      flash[:error] = "#{masqueraded_resource_class} not found."
      redirect_to(new_user_session_path) and return
    end

    request.env['devise.skip_trackable'] = '1'

    masquerade_sign_in(resource)

    go_back(resource, path: after_masquerade_full_path_for(resource))
  end

  def back
    user_id = session[session_key]

    resource = if user_id.present?
      masquerading_resource_class.to_adapter.find_first(:id => user_id)
    else
      send(:"current_#{masquerading_resource_name}")
    end

    if masquerading_resource_class == masqueraded_resource_class
      sign_out(send("current_#{masqueraded_resource_name}"))
    end

    masquerade_sign_in(resource)
    request.env['devise.skip_trackable'] = nil

    go_back(resource, path: after_back_masquerade_path_for(resource))
  end

  protected

  def masquerade_authorize!
    head(403) unless masquerade_authorized?
  end

  def masquerade_authorized?
    true
  end

  def find_resource
    masqueraded_resource_class.
      find_by_masquerade_key(params[Devise.masquerade_param]).
      where(id: params[:id]).
      first
  end

  def go_back(user, path:)
    if Devise.masquerade_routes_back
      redirect_back(fallback_location: path)
    else
      redirect_to path
    end
  end

  private

  def masqueraded_resource_class
    @masqueraded_resource_class ||= begin
      unless params[:masqueraded_resource_class].blank?
        params[:masqueraded_resource_class].constantize
      else
        unless session[session_key_masqueraded_resource_class].blank?
          session[session_key_masquerading_resource_class].constantize
        else
          Devise.masqueraded_resource_class || resource_class
        end
      end
    end
  end

  def masqueraded_resource_name
    Devise.masqueraded_resource_name || masqueraded_resource_class.model_name.param_key
  end

  def masquerading_resource_class
    @masquerading_resource_class ||= begin
      unless params[:masquerading_resource_class].blank?
        params[:masquerading_resource_class].constantize
      else
        unless session[session_key_masquerading_resource_class].blank?
          session[session_key_masquerading_resource_class].constantize
        else
          Devise.masquerading_resource_class || resource_class
        end
      end
    end
  end

  def masquerading_resource_name
    Devise.masquerading_resource_name || masquerading_resource_class.model_name.param_key
  end

  def authenticate_scope!
    send(:"authenticate_#{masquerading_resource_name}!", force: true)
  end

  def after_masquerade_path_for(resource)
    coach_path
  end

  def after_masquerade_full_path_for(resource)
    after_masquerade_path_for(resource)
  end

  def after_back_masquerade_path_for(resource)
    coaches_path
  end

  def save_masquerade_owner_session
    unless session.key?(session_key)
      session[session_key] = send("current_#{masquerading_resource_name}").id
      session[session_key_masquerading_resource_class] = masquerading_resource_class.name
      session[session_key_masqueraded_resource_class] = masqueraded_resource_class.name
    end
  end

  def cleanup_masquerade_owner_session
    session.delete(session_key)
    session.delete(session_key_masqueraded_resource_class)
    session.delete(session_key_masquerading_resource_class)
  end

  def session_key
    "devise_masquerade_#{masqueraded_resource_name}".to_sym
  end

  def session_key_masqueraded_resource_class
    "devise_masquerade_masqueraded_resource_class"
  end

  def session_key_masquerading_resource_class
    "devise_masquerade_masquerading_resource_class"
  end
end
