module ApiBlueprint::Collect::ControllerHook
  def self.included(base)
    return unless ENV['API_BLUEPRINT_DUMP'] == '1'

    if base.respond_to?(:before_action)
      base.before_action :set_blueprint_args
    else
      base.before_filter :set_blueprint_args
    end

  end

  def set_blueprint_args
    ApiBlueprint::Collect::SpecHook.controller_name = controller_name
    ApiBlueprint::Collect::SpecHook.action_name = action_name
  end

end
