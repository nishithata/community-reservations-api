module Api
  module V1
    class ReservationsController < ApplicationController
      before_action :set_reservation, only: %i[show cancel]

      rate_limit to: 30, within: 1.minute, only: :create, by: -> { current_user.id }, with: -> {
        render_error(:too_many_requests, "rate_limited", "Too many reservations created. Please slow down.")
      }

      # GET /api/v1/reservations?status=confirmed&resource_id=1&from=...&to=...&page=1
      def index
        scope = ReservationPolicy.scope(current_user).includes(:resource, :user).chronological
        scope = scope.where(status: status_filter) if params[:status].present?
        scope = scope.where(resource_id: params[:resource_id]) if params[:resource_id].present?
        scope = scope.where("ends_at > ?", time_param(:from)) if params[:from].present?
        scope = scope.where("starts_at < ?", time_param(:to)) if params[:to].present?

        records, meta = paginate(scope)
        render json: { data: records.map { ReservationSerializer.call(it) }, meta: }
      end

      # GET /api/v1/reservations/:id
      def show
        authorize!(@reservation, :show?)
        render json: { data: ReservationSerializer.call(@reservation) }
      end

      # POST /api/v1/reservations
      #
      # Overlaps are rejected twice: by a model validation (friendly 409 in the common
      # case) and by a PostgreSQL exclusion constraint that also catches two requests
      # racing for the same slot. Both paths return 409 reservation_conflict.
      def create
        reservation = current_user.reservations.new(reservation_params)
        reservation.save!

        render json: { data: ReservationSerializer.call(reservation) }, status: :created,
          location: api_v1_reservation_url(reservation)
      end

      # PATCH /api/v1/reservations/:id/cancel
      def cancel
        authorize!(@reservation, :cancel?)
        @reservation.cancel!

        render json: { data: ReservationSerializer.call(@reservation) }
      end

      private

      # Scoping the lookup means members get 404 (not 403) for other people's
      # reservations, so the API doesn't reveal which IDs exist.
      def set_reservation
        @reservation = ReservationPolicy.scope(current_user).includes(:resource, :user).find(params[:id])
      end

      def reservation_params
        params.expect(reservation: %i[resource_id starts_at ends_at notes])
      end

      def status_filter
        status = params[:status].to_s
        return status if Reservation.statuses.key?(status)

        raise Errors::BadRequest, "status must be one of: #{Reservation.statuses.keys.join(', ')}"
      end

      def time_param(key)
        Time.iso8601(params[key].to_s)
      rescue ArgumentError
        raise Errors::BadRequest, "#{key} must be an ISO 8601 timestamp"
      end
    end
  end
end
