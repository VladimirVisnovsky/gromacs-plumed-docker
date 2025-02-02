FROM nvidia/cuda:11.2.1-devel-ubuntu20.04 as builder
MAINTAINER Ales Krenek <ljocha@ics.muni.cz> 

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Prague

ARG JOBS=8

#ARG FFTW_VERSION=3.3.9
#ARG FFTW_MD5=50145bb68a8510b5d77605f11cadf8dc


#enable contributed packages
#RUN sed -i 's/main/main contrib/g' /etc/apt/sources.list

RUN cat /etc/apt/sources.list
#install dependencies
RUN apt-get update 
RUN apt-get install -y cmake g++ gcc 
RUN apt-get install -y libblas-dev xxd 
RUN apt-get install -y mpich libmpich-dev 
RUN apt-get install -y curl
RUN apt-get install -y unzip
# RUN apt-get install -y libfftw3-dev

RUN mkdir /build
WORKDIR /build

#RUN curl -o fftw.tar.gz http://www.fftw.org/fftw-${FFTW_VERSION}.tar.gz 
#RUN echo ${FFTW_MD5} fftw.tar.gz > fftw.tar.gz.md5 && md5sum -c fftw.tar.gz.md5
#
#RUN tar -xzvf fftw.tar.gz && cd fftw-${FFTW_VERSION} \
#  && ./configure --disable-double --enable-float --enable-sse2 --enable-avx --enable-avx2 --enable-avx512 --enable-shared --disable-static \
#  && make -j ${JOBS} \
#  && make install

ARG PLUMED_VERSION=uvt_extensions

RUN apt-get update
RUN apt-get install -y git

# interim, before our changes are pushed to mainstream
ENV GIT_SSL_NO_VERIFY=true
RUN git clone https://github.com/kurecka/plumed2.git plumed2 --branch ${PLUMED_VERSION} --single-branch

RUN cd /build && \
    curl https://download.pytorch.org/libtorch/cpu/libtorch-cxx11-abi-shared-with-deps-1.12.1%2Bcpu.zip --output torch.zip && \
    unzip torch.zip && \
    rm torch.zip

ENV LIBTORCH=/build/libtorch
ENV CPATH=${LIBTORCH}/include/torch/csrc/api/include/:${LIBTORCH}/include/:${LIBTORCH}/include/torch:$CPATH
ENV INCLUDE=${LIBTORCH}/include/torch/csrc/api/include/:${LIBTORCH}/include/:${LIBTORCH}/include/torch:$INCLUDE
ENV LIBRARY_PATH=${LIBTORCH}/lib:$LIBRARY_PATH
ENV LD_LIBRARY_PATH=${LIBTORCH}/lib:$LD_LIBRARY_PATH

RUN cd plumed2 && ./configure --enable-libtorch --enable-modules=all --enable-debug && make -j ${JOBS} && make install 
RUN ldconfig

RUN apt update
RUN apt install -y python3

ARG GROMACS_VERSION=2021
ARG GROMACS_MD5=176f7decc09b23d79a495107aaedb426
ARG GROMACS_PATCH_VERSION=${GROMACS_VERSION}

RUN curl -o gromacs.tar.gz https://ftp.gromacs.org/gromacs/gromacs-${GROMACS_VERSION}.tar.gz
RUN echo ${GROMACS_MD5} gromacs.tar.gz > gromacs.tar.gz.md5 && md5sum -c gromacs.tar.gz.md5

RUN tar -xzvf gromacs.tar.gz
RUN cd gromacs-${GROMACS_VERSION} && plumed patch -e gromacs-${GROMACS_PATCH_VERSION} -p

COPY build-gmx.sh /build
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a SSE2
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a SSE2 -d

RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX2_256 -r
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX2_256 -r -d

RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX_512 -r
RUN ./build-gmx.sh -s gromacs-${GROMACS_VERSION} -j ${JOBS} -a AVX_512 -r -d


RUN apt-get install -y python3 python3-pip
RUN pip3 install torch --extra-index-url https://download.pytorch.org/whl/cpu

FROM nvidia/cuda:11.2.1-runtime-ubuntu20.04

RUN apt update
RUN apt install -y mpich
RUN apt install -y libcufft10 libmpich12 libblas3 libgomp1 

COPY --from=builder /build/libtorch /build/libtorch
ENV LD_LIBRARY_PATH=/build/libtorch/lib:$LD_LIBRARY_PATH
ENV CPLUS_INCLUDE_PATH=/build/libtorch/include:$CPLUS_INCLUDE_PATH

COPY --from=builder /build/libtorch/lib/* /usr/local/lib/
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /usr/local/lib/libplumed* /usr/local/lib/
COPY --from=builder /usr/local/lib/plumed/ /usr/local/lib/plumed/

COPY --from=builder /gromacs /gromacs

COPY gmx-chooser.sh /gromacs
COPY gmx /usr/local/bin
RUN ln -s gmx /usr/local/bin/gmx_d
RUN ln -s gmx /usr/local/bin/mdrun
RUN ln -s gmx /usr/local/bin/mdrun_d

RUN apt clean
RUN ldconfig
