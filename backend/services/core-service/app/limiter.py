"""
Limite de débit (rate limiting), partagée par tous les routeurs.

Protège contre un client (ou un attaquant) qui enverrait des centaines de
requêtes par seconde : force brute sur un mot de passe ou un code de
récupération, création massive de comptes, ou saturation du CPU par les
modèles vocaux. L'adresse IP ne sert qu'à ce compteur EN MÉMOIRE : elle
n'est jamais écrite en base (règle de confidentialité n°2).
"""

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)
