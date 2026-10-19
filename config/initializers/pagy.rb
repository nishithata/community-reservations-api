# Pagination defaults for API list endpoints.
# Clients may request ?page=N and ?per_page=N (capped at client_limit).
Pagy::OPTIONS[:limit] = 20
Pagy::OPTIONS[:limit_key] = "per_page"
Pagy::OPTIONS[:client_limit] = 100
