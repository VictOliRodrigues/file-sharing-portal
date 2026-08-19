module ApplicationHelper
  def portal_name
    Rails.application.config.x.portal.app_name
  end

  # Whether the sign up form should be advertised. The first account may always
  # be created so a fresh deployment can be bootstrapped.
  def registration_open?
    Rails.application.config.x.portal.registration_enabled || User.none?
  end

  def flash_classes(type)
    case type.to_s
    when "notice", "success" then "bg-emerald-50 text-emerald-800 ring-emerald-200"
    when "alert", "error"    then "bg-red-50 text-red-800 ring-red-200"
    else                          "bg-slate-50 text-slate-700 ring-slate-200"
    end
  end

  # Renders a byte count the way a file manager would.
  def human_size(bytes)
    number_to_human_size(bytes.to_i, precision: 3, significant: false, strip_insignificant_zeros: true)
  end

  def form_errors_for(record)
    return if record.errors.empty?

    render "shared/form_errors", record: record
  end

  def nav_link_to(name, path, active:, icon: nil)
    link_to path, class: active ? "nav-link-active" : "nav-link" do
      safe_join([ icon && inline_icon(icon), tag.span(name) ].compact)
    end
  end
end
