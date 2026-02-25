from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://gradpath:gradpath_pw@localhost:5432/gradpath"
    jwt_secret: str = "change_me_in_production"
    environment: str = "development"

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
