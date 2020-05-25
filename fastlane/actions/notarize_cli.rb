module Fastlane
  module Actions
    module SharedValues
    end

    # NOTE: based on copy of https://github.com/fastlane/fastlane/blob/master/fastlane/lib/fastlane/actions/notarize.rb
    class NotarizeCliAction < NotarizeAction
      def self.staple(package_path, verbose)
        # a single binary cli cannot be stapled so far:
        # The staple and validate action failed! Error 73.
        UI.important "Skipping staple. The binary is notarized and can be distributed but not stapled: #{package_path}"
      end
    end
  end
end
