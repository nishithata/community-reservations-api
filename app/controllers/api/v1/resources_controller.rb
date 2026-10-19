module Api
  module V1
    class ResourcesController < ApplicationController
      allow_unauthenticated only: %i[index show availability]
      before_action :set_resource, only: %i[show update destroy availability]

      # GET /api/v1/resources?category=room&q=garden&page=1&per_page=20
      def index
        scope = ResourcePolicy.scope(current_user).order(:name)
        scope = scope.where(category: category_filter) if params[:category].present?
        scope = scope.search(params[:q]) if params[:q].present?
        scope = scope.where(active: boolean_param(:active)) if params.key?(:active)

        records, meta = paginate(scope)
        render json: { data: records.map { ResourceSerializer.call(it) }, meta: }
      end

      # GET /api/v1/resources/:id
      def show
        render json: { data: ResourceSerializer.call(@resource) }
      end

      # POST /api/v1/resources (admin)
      def create
        resource = Resource.new(resource_params)
        authorize!(resource, :create?)
        resource.save!

        render json: { data: ResourceSerializer.call(resource) }, status: :created,
          location: api_v1_resource_url(resource)
      end

      # PATCH /api/v1/resources/:id (admin)
      def update
        authorize!(@resource, :update?)
        @resource.update!(resource_params)

        render json: { data: ResourceSerializer.call(@resource) }
      end

      # DELETE /api/v1/resources/:id (admin)
      # Resources with reservation history cannot be deleted; deactivate them instead.
      def destroy
        authorize!(@resource, :destroy?)
        @resource.destroy!

        head :no_content
      end

      # GET /api/v1/resources/:id/availability?date=2026-10-20
      # Lists confirmed bookings for the UTC day without exposing who made them.
      def availability
        date = parse_date(params.require(:date))
        bookings = @resource.bookings_on(date).map do |reservation|
          { starts_at: reservation.starts_at.iso8601, ends_at: reservation.ends_at.iso8601 }
        end

        render json: { data: { resource_id: @resource.id, date: date.iso8601, bookings: } }
      end

      private

      # Inactive resources are invisible (404) to everyone except admins.
      def set_resource
        @resource = ResourcePolicy.scope(current_user).find(params[:id])
      end

      def resource_params
        params.expect(resource: %i[name description category location capacity active])
      end

      def category_filter
        category = params[:category].to_s
        return category if Resource.categories.key?(category)

        raise Errors::BadRequest, "category must be one of: #{Resource.categories.keys.join(', ')}"
      end

      def boolean_param(key)
        value = ActiveModel::Type::Boolean.new.cast(params[key])
        raise Errors::BadRequest, "#{key} must be true or false" if value.nil?

        value
      end

      def parse_date(value)
        Date.iso8601(value)
      rescue Date::Error
        raise Errors::BadRequest, "date must be an ISO 8601 date (YYYY-MM-DD)"
      end
    end
  end
end
