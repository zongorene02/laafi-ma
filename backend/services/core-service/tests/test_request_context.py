"""Vérifie l'identifiant de requête renvoyé au client (voir request_context.py).

Il sert de point de raccroche entre ce que voit l'utilisateur ("j'ai eu une
erreur") et ce qu'a écrit le serveur : sans lui, retrouver les bonnes lignes
de log dans un flux où plusieurs requêtes s'entremêlent relève de la
devinette à partir d'un horodatage approximatif."""

from app.request_context import REQUEST_ID_HEADER


def test_every_response_carries_a_request_id(client):
    response = client.get("/health")
    assert response.headers.get(REQUEST_ID_HEADER)


def test_two_requests_get_different_ids(client):
    first = client.get("/health").headers[REQUEST_ID_HEADER]
    second = client.get("/health").headers[REQUEST_ID_HEADER]
    assert first != second


def test_an_incoming_request_id_is_preserved(client):
    """Un identifiant déjà posé en amont (reverse proxy, load balancer) est
    conservé : la même requête garde le même identifiant sur toute la chaîne,
    sinon corréler nos logs avec ceux du proxy redevient impossible."""
    response = client.get("/health", headers={REQUEST_ID_HEADER: "trace-venant-du-proxy"})
    assert response.headers[REQUEST_ID_HEADER] == "trace-venant-du-proxy"


def test_the_id_survives_an_error_response(client):
    """C'est précisément sur une erreur qu'on a besoin de cet identifiant :
    il doit être présent aussi quand la requête échoue."""
    response = client.get("/auth/me")  # 401 : pas de jeton
    assert response.status_code == 401
    assert response.headers.get(REQUEST_ID_HEADER)
