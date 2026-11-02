"""kb capsule seed key

Clé stable des réponses et capsules créées par `python -m app.seed`, comme
`danger_signs.seed_key` : le seed reste idempotent même si un validateur a
modifié le texte depuis. Colonne facultative : les contenus saisis dans la
console n'en ont pas.

Le statut `sourced` n'a pas besoin de migration : `status` est une simple
chaîne de 20 caractères.

Revision ID: c3d9f5a17e42
Revises: b7c2e4a91d30
Create Date: 2026-10-30 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c3d9f5a17e42'
down_revision: Union[str, Sequence[str], None] = 'b7c2e4a91d30'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Mode batch : SQLite ne sait pas ajouter une contrainte d'unicité avec
    # ALTER TABLE (voir b7c2e4a91d30).
    with op.batch_alter_table('kb_entries') as batch_op:
        batch_op.add_column(sa.Column('seed_key', sa.String(length=80), nullable=True))
        batch_op.create_unique_constraint('uq_kb_entries_seed_key', ['seed_key'])
    with op.batch_alter_table('capsules') as batch_op:
        batch_op.add_column(sa.Column('seed_key', sa.String(length=80), nullable=True))
        batch_op.create_unique_constraint('uq_capsules_seed_key', ['seed_key'])


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('capsules') as batch_op:
        batch_op.drop_constraint('uq_capsules_seed_key', type_='unique')
        batch_op.drop_column('seed_key')
    with op.batch_alter_table('kb_entries') as batch_op:
        batch_op.drop_constraint('uq_kb_entries_seed_key', type_='unique')
        batch_op.drop_column('seed_key')
