import os

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine


def get_engine() -> Engine:
    """
    Create and return a SQLAlchemy engine using the
    NOVA_SQLALCHEMY_URL environment variable.
    """

    connection_string = os.getenv("NOVA_SQLALCHEMY_URL")

    if not connection_string:
        raise RuntimeError(
            "Environment variable NOVA_SQLALCHEMY_URL is not set."
        )

    return create_engine(
        connection_string,
        fast_executemany=True,
    )