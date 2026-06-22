FROM wordpress:latest

RUN apt-get update && apt-get install -y \
    libpq-dev \
    unzip \
    git \
    && docker-php-ext-install pdo pdo_pgsql pgsql

RUN git clone --branch v3.4.1 https://github.com/PostgreSQL-For-Wordpress/postgresql-for-wordpress.git /tmp/pg4wp-repo \
    && cp -r /tmp/pg4wp-repo/pg4wp /var/www/html/wp-content/pg4wp \
    && cp /var/www/html/wp-content/pg4wp/db.php /var/www/html/wp-content/db.php \
    && rm -rf /tmp/pg4wp-repo
