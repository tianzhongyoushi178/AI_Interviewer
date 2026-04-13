# frozen_string_literal: true

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :data, 'https://fonts.gstatic.com', 'https://cdn.jsdelivr.net'
  policy.img_src     :self, :data, :https
  policy.object_src  :none
  policy.script_src  :self, 'https://cdn.jsdelivr.net', 'https://www.googletagmanager.com', :unsafe_inline
  policy.style_src   :self, 'https://cdn.jsdelivr.net', 'https://fonts.googleapis.com', :unsafe_inline
  policy.connect_src :self
  policy.media_src   :self, :blob
  policy.frame_src   :none
end

# UJS nonce generation
# Rails.application.config.content_security_policy_nonce_generator = -> request { SecureRandom.base64(16) }
