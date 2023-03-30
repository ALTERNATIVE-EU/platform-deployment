# syntax = docker/dockerfile:1.3
# The build stage
# ---------------
FROM python:3.9-bullseye as build-stage

# VULN_SCAN_TIME=2022-08-08_05:22:22

WORKDIR /build-stage

# set pip's cache directory using this environment variable, and use
# ARG instead of ENV to ensure its only set when the image is built
ARG PIP_CACHE_DIR=/tmp/pip-cache

# These are mounted into the final image for installation
COPY requirements.txt requirements.txt
RUN --mount=type=cache,target=${PIP_CACHE_DIR} \
    pip install build \
 && pip wheel -r requirements.txt


# The final stage
# ---------------

FROM python:3.9-slim-bullseye

# VULN_SCAN_TIME=

ENV DEBIAN_FRONTEND=noninteractive \
    NB_USER=jovyan \
    NB_UID=1000 \
    HOME=/home/jovyan

RUN adduser --disabled-password \
        --gecos "Default user" \
        --uid ${NB_UID} \
        --home ${HOME} \
        --force-badname \
        ${NB_USER}

RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        dnsutils \
        iputils-ping \
        tini \
        vim \
        # requirement for nbgitpuller
        git \
        # anaconda
        wget \
        openssh-client \
        sudo \
        iproute2 \
 && rm -rf /var/lib/apt/lists/*

# set pip's cache directory using this environment variable, and use
# ARG instead of ENV to ensure its only set when the image is built
ARG PIP_CACHE_DIR=/tmp/pip-cache

# install wheels built in the build-stage
COPY requirements.txt /tmp/requirements.txt
RUN --mount=type=cache,target=${PIP_CACHE_DIR} \
    --mount=type=cache,from=build-stage,source=/build-stage,target=/tmp/wheels \
    pip install \
        --find-links=/tmp/wheels/ \
        -r /tmp/requirements.txt

RUN mkdir /var/alternative-anaconda
COPY init_conda.sh /var/alternative-anaconda/init_conda.sh
COPY activate_conda.sh /var/alternative-anaconda/activate_conda.sh
COPY init.sh /var/alternative-anaconda/init.sh
RUN chown -R ${NB_USER}:${NB_USER} /var/alternative-anaconda
RUN chmod 755 /var/alternative-anaconda/init_conda.sh
RUN chmod 755 /var/alternative-anaconda/activate_conda.sh
RUN chmod 755 /var/alternative-anaconda/init.sh

USER ${NB_USER}
WORKDIR /var/alternative-anaconda

RUN wget https://repo.anaconda.com/archive/Anaconda3-2022.10-Linux-x86_64.sh
RUN bash ./Anaconda3-2022.10-Linux-x86_64.sh -b -p /var/alternative-anaconda/anaconda3
RUN rm ./Anaconda3-2022.10-Linux-x86_64.sh

RUN touch /home/jovyan/.bashrc
RUN echo 'export PATH=/var/alternative-anaconda/anaconda3/bin:$PATH' >> /home/jovyan/.bashrc

RUN /var/alternative-anaconda/anaconda3/bin/conda install -c conda-forge jupyterlab
RUN /var/alternative-anaconda/anaconda3/bin/conda install -c conda-forge notebook
RUN /var/alternative-anaconda/anaconda3/bin/conda install -c conda-forge nb_conda
RUN /var/alternative-anaconda/anaconda3/bin/conda install -c conda-forge nb_conda_kernels
RUN /var/alternative-anaconda/anaconda3/bin/conda install -c conda-forge jupyter_contrib_nbextensions
RUN /var/alternative-anaconda/anaconda3/bin/conda install -c anaconda ipykernel
RUN /var/alternative-anaconda/anaconda3/bin/conda create --name Conda
RUN bash -i ./init_conda.sh
RUN bash -i ./activate_conda.sh
RUN rm ./init_conda.sh
RUN rm ./activate_conda.sh

RUN mkdir /var/alternative-anaconda/init-home
RUN cp -R /home/jovyan/ /var/alternative-anaconda/init-home/

COPY python_kernel.json /usr/local/share/jupyter/kernels/python3/kernel.json

WORKDIR ${HOME}

EXPOSE 8888
ENTRYPOINT ["tini", "--"]
CMD ["/var/alternative-anaconda/init.sh"]
