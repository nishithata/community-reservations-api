module Api
  module V1
    # Deep health check: unlike /up, this also verifies the database connection.
    class HealthController < ApplicationController
      skip_before_action :authenticate!

      def show
        ActiveRecord::Base.connection.select_value("SELECT 1")
        render json: { status: "ok", database: "ok", time: Time.current.iso8601 }
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.error("Health check failed: #{e.class}: #{e.message}")
        render json: { status: "error", database: "unavailable" }, status: :service_unavailable
      end
    end
  end
end
