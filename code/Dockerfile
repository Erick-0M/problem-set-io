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


# Julia 1.12 + IJulia kernel (the base image only ships Julia 1.9). Packages are managed by the
# project-local environment in scripts/julia (Project.toml/Manifest.toml); see README.
ARG JULIA_VERSION=1.12.5
ENV JULIA_DEPOT_PATH=/opt/julia_depot
RUN case "$(uname -m)" in \
      aarch64) JARCH=aarch64; JDIR=aarch64 ;; \
      *) JARCH=x86_64; JDIR=x64 ;; \
    esac \
 && curl -fsSL "https://julialang-s3.julialang.org/bin/linux/${JDIR}/${JULIA_VERSION%.*}/julia-${JULIA_VERSION}-linux-${JARCH}.tar.gz" \
    | tar -xz -C /opt \
 && ln -sf /opt/julia-${JULIA_VERSION}/bin/julia /usr/local/bin/julia-1.12 \
 && mkdir -p ${JULIA_DEPOT_PATH} && chown -R ${NB_UID}:${NB_GID} ${JULIA_DEPOT_PATH}
USER ${NB_UID}
RUN julia-1.12 -e 'using Pkg; Pkg.add("IJulia"); using IJulia; \
      installkernel("Julia 1.12 (project)", "--project=/home/repo-intro/scripts/julia"; specname="julia-project", env=Dict("JULIA_DEPOT_PATH"=>"/opt/julia_depot"))'
USER root

RUN mkdir /home/repo-intro
RUN cd /home/repo-intro
WORKDIR /home/repo-intro

RUN mkdir /home/repo-intro/build
RUN mkdir /home/repo-intro/analysis

ENV NOTEBOOK_ARGS="--NotebookApp.token='' --NotebookApp.password=''"
COPY requirements.txt .
RUN pip install -r requirements.txt

EXPOSE 8888