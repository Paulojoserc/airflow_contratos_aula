FROM apache/airflow:3.0.2-python3.12
RUN pip install --no-cache-dir pandas
COPY dags/ /opt/airflow/dags/
COPY plugins/ /opt/airflow/plugins/