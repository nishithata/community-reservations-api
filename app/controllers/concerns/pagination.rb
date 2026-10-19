# Offset pagination with Pagy. Clients pass ?page=N&per_page=N (per_page capped at 100).
module Pagination
  include Pagy::Method

  private

  def paginate(scope)
    pagy, records = pagy(:offset, scope)
    [ records, pagination_meta(pagy) ]
  end

  def pagination_meta(pagy)
    {
      page: pagy.page,
      per_page: pagy.limit,
      total_count: pagy.count,
      total_pages: pagy.last,
      next_page: pagy.next,
      prev_page: pagy.previous
    }
  end
end
