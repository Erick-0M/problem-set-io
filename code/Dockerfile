FROM jupyter/datascience-notebook:latest

USER ${NB_UID}

RUN pip install dbfread
RUN pip install linearmodels
RUN pip install geopandas


USER root
RUN sudo apt-get update
RUN sudo apt-get install -y tesseract-ocr
RUN pip install pytesseract
RUN pip install google-cloud-bigquery pandas-gbq google-cloud-storage pyarrow
RUN pip install gcsfs tqdm polars
RUN pip install bigframes
RUN pip install pyreadstat
RUN pip install pyblp pdfplumber rapidfuzz networkx
#


RUN mkdir /home/repo-intro
RUN cd /home/repo-intro
WORKDIR /home/repo-intro

RUN mkdir /home/repo-intro/build
RUN mkdir /home/repo-intro/analysis

ENV NOTEBOOK_ARGS="--NotebookApp.token='' --NotebookApp.password=''"
COPY requirements.txt .
RUN pip install -r requirements.txt

EXPOSE 8888