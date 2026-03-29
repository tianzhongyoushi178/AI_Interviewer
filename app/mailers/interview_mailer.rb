# app/mailers/interview_mailer.rb
class InterviewMailer < ApplicationMailer
  default from: ENV.fetch('MAILER_FROM_ADDRESS', 'info@okey.work')

  # 不合格通知メール
  def rejection_notification(interview, reason)
    @interview = interview
    @user = interview.user
    @situation = interview.situation
    @reason = reason

    mail(
      to: @user.email,
      subject: "面接結果のご連絡 - #{@situation.title}"
    )
  end
end
