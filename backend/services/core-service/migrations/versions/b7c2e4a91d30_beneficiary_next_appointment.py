"""beneficiary next appointment

Prochain rendez-vous d'une bénéficiaire (liste « Rappels à faire » de
l'agent) : deux colonnes facultatives, donc sans valeur à inventer pour les
fiches existantes.

Les fiches d'aide de l'agent sur les signes de danger (`agent_questions`,
`refer_when`) n'ont pas besoin de migration : elles vivent dans la colonne
JSON `danger_signs.translations`, et les lignes anciennes reçoivent leurs
valeurs par défaut à la lecture (voir app/content.py).

Revision ID: b7c2e4a91d30
Revises: 10474e16e13f
Create Date: 2026-10-29 16:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b7c2e4a91d30'
down_revision: Union[str, Sequence[str], None] = '10474e16e13f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # `batch_alter_table` : SQLite ne sait pas tout faire avec ALTER TABLE ;
    # en mode batch Alembic recrée la table si besoin (sans effet sur
    # PostgreSQL, qui reçoit un ALTER TABLE classique).
    with op.batch_alter_table('beneficiaries') as batch_op:
        batch_op.add_column(sa.Column('next_appointment_date', sa.Date(), nullable=True))
        batch_op.add_column(sa.Column('next_appointment_reason', sa.String(length=30), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    with op.batch_alter_table('beneficiaries') as batch_op:
        batch_op.drop_column('next_appointment_reason')
        batch_op.drop_column('next_appointment_date')
