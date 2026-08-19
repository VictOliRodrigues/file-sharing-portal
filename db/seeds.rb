# Seed data.
#
# Running `bin/rails db:seed` creates the first administrator account when
# ADMIN_EMAIL and ADMIN_PASSWORD are present in the environment. It is safe to
# run repeatedly: an existing account is never modified.
#
# Alternatively, simply register through the web interface -- the first account
# created on an empty installation automatically becomes an administrator.

admin_email = ENV["ADMIN_EMAIL"].presence
admin_password = ENV["ADMIN_PASSWORD"].presence

if admin_email && admin_password
  user = User.find_by(email_address: admin_email.downcase.strip)

  if user
    puts "Administrator #{user.email_address} already exists; leaving it untouched."
  else
    User.create!(
      name: ENV.fetch("ADMIN_NAME", "Administrator"),
      email_address: admin_email,
      password: admin_password,
      password_confirmation: admin_password,
      admin: true
    )
    puts "Created administrator #{admin_email}."
  end
else
  puts "ADMIN_EMAIL and ADMIN_PASSWORD are not set; skipping administrator creation."
  puts "The first account registered through the web interface becomes an administrator."
end
