Logger.configure(level: :info)

if System.get_env("CIRCLECI") == "true" do
  ExUnit.start(capture_log: true, max_cases: 1)
else
  ExUnit.start(capture_log: true)
end
