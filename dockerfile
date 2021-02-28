FROM postgres:12

RUN apt-get update \
    && apt-get install -y \
        postgresql-12-pgtap \
        postgresql-12-cron \
        postgresql-12-python3-multicorn \
        postgresql-12-partman \
        postgresql-plpython3-12 \
        python3-pip


COPY requirements.txt /requirements.txt
RUN pip3 install -r /requirements.txt

COPY httpx.sql /httpx.sql
COPY dev.sql /dev.sql
COPY dev.py /dev.py

WORKDIR /work

# extra port
EXPOSE 80
