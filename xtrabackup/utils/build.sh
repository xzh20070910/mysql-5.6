#!/usr/bin/env bash

set -e

MYSQL_51_VERSION=5.1.59
MYSQL_55_VERSION=5.5.17
MYSQL_56_VERSION=5.6.10
PS_51_VERSION=5.1.59-13.0
PS_55_VERSION=5.5.16-22.0

if [ -r ../CMakeCache.txt ]; then
  echo BUILD_TYPE= ${BUILD_TYPE:="$(grep CMAKE_BUILD_TYPE:STRING= ../CMakeCache.txt | cut -f2 -d=)"}
  echo SRC_DIR= ${SRC_DIR:="$(grep MySQL_SOURCE_DIR:STATIC= ../CMakeCache.txt | cut -f2 -d=)"}
  echo CMAKE= ${CMAKE:="$(grep CMAKE_COMMAND:INTERNAL= ../CMakeCache.txt | cut -f2 -d=)"}
  echo CXX= ${CXX:="$(grep CMAKE_CXX_COMPILER:FILEPATH= ../CMakeCache.txt | cut -f2 -d=) $(grep CMAKE_CXX_COMPILER_ARG1:STRING= ../CMakeCache.txt | cut -f2 -d=)"}
  echo CC= ${CC:="$(grep CMAKE_C_COMPILER:FILEPATH= ../CMakeCache.txt | cut -f2 -d=) $(grep CMAKE_C_COMPILER_ARG1:STRING= ../CMakeCache.txt | cut -f2 -d=)"}
  echo CXXFLAGS= ${CXXFLAGS:="$(grep CMAKE_CXX_FLAGS:STRING= ../CMakeCache.txt | cut -f2 -d=) $(grep CMAKE_C_COMPILER_ARG1:STRING= ../CMakeCache.txt | cut -f2 -d=)"}
  echo CFLAGS= ${CFLAGS:="$(grep CMAKE_C_FLAGS:STRING= ../CMakeCache.txt | cut -f2 -d=) $(grep CMAKE_C_COMPILER_ARG1:STRING= ../CMakeCache.txt | cut -f2 -d=)"}
else
  echo BUILD_TYPE= ${BUILD_TYPE:=Release}
  echo SRC_DIR= ${SRC_DIR:=$(readlink -f ..)}
  echo CMAKE= ${CMAKE:=cmake}
  echo CXX= ${CXX:=g++}
  echo CC= ${CC:=gcc}
  echo CXXFLAGS= ${CXXFLAGS:-}
  echo CFLAGS= ${CFLAGS:-}
fi

export CC="$CC"
export CXX="$CXX"
export CFLAGS="$CFLAGS -DXTRABACKUP"
export CXXFLAGS="$CFLAGS -fno-rtti -fno-exceptions"
export LDFLAGS="$LDFLAGS"
export SRC_DIR="$SRC_DIR"
export BUILD_TYPE="$BUILD_TYPE"

MAKE_CMD=make
if gmake --version > /dev/null 2>&1
then
	MAKE_CMD=gmake
fi
MAKE_CMD="$MAKE_CMD -j6"

function usage()
{
    echo "Build an xtrabackup binary against the specified InnoDB flavor."
    echo
    echo "Usage: `basename $0` CODEBASE"
    echo "where CODEBASE can be one of the following values or aliases:"
    echo "  innodb56         | 5.6                   build against InnoDB in MySQL 5.6"
    exit -1
}

################################################################################
# Invoke 'make' in the specified directoies
################################################################################
function make_dirs()
{
    for d in $*
    do
	$MAKE_CMD -C $d
    done
}

function build_server()
{
    local $type=$1
    echo "Configuring the server"
    cd $server_dir
    echo eval $configure_cmd
    eval $configure_cmd

    echo "Building the server"
    make_dirs libmysqld
    cd $top_dir
}

function build_libarchive()
{
	echo "Building libarchive"
	cd $top_dir/src/libarchive

	${CMAKE}  . \
	    -DENABLE_CPIO=OFF \
	    -DENABLE_OPENSSL=OFF \
	    -DENABLE_TAR=OFF \
	    -DENABLE_TEST=OFF
	$MAKE_CMD || exit -1
}

function build_xtrabackup()
{
    build_libarchive
    echo "Building XtraBackup"

    # Read XTRABACKUP_VERSION from the VERSION file
    . $top_dir/VERSION

    cd $top_dir/src
    if [ "`uname -s`" = "Linux" ]
    then
	export LIBS="$LIBS -lrt"
    fi
    $MAKE_CMD MYSQL_ROOT_DIR=$server_dir clean
    $MAKE_CMD MYSQL_ROOT_DIR=$server_dir XTRABACKUP_VERSION=$XTRABACKUP_VERSION $xtrabackup_target
    cd $top_dir
}


################################################################################
# Do all steps to build the server, xtrabackup and xbstream
# Expects the following variables to be set before calling:
#   mysql_version	version string (e.g. "5.1.53")
#   server_patch	name of the patch to apply to server source before
#                       building (e.g. "xtradb51.patch")
#   innodb_name		either "innobase" or "innodb_plugin"
#   configure_cmd	server configure command
#   xtrabackup_target	'make' target to build in the xtrabackup build directory
#
################################################################################
function build_all()
{
    local type=$1

    mkdir -p $server_dir
    build_server $type

    build_xtrabackup
}

if ! test -f src/xtrabackup.cc
then
	echo "`basename $0` must be run from the directory with XtraBackup sources"
	usage
fi

type=$1
top_dir=`pwd`


case "$type" in
"innodb56" | "5.6")
        mysql_version=$MYSQL_56_VERSION
        server_patch=innodb56.patch
        innodb_name=innobase
        xtrabackup_target=5.6
        mysql_version_short=${mysql_version:0:3}
        server_dir=$top_dir/mysql-$mysql_version_short
        configure_cmd="${CMAKE} $SRC_DIR \
                -DWITH_INNOBASE_STORAGE_ENGINE=ON \
                -DWITH_ZLIB=bundled \
                -DWITH_EXTRA_CHARSETS=all \
                -DWITH_EMBEDDED_SERVER=1 \
                -DMYSQL_ROOT_DIR=$server_dir \
                -DCMAKE_BUILD_TYPE=$BUILD_TYPE"
        if [ -n "$CURSES_LIBRARY" ]; then
                configure_cmd+=" -DCURSES_LIBRARY=$CURSES_LIBRARY"
        fi
        if [ -n "$CURSES_INCLUDE_PATH" ]; then
                configure_cmd+=" -DCURSES_INCLUDE_PATH=$CURSES_INCLUDE_PATH"
        fi
        build_all $type
        ;;

*)
	usage
	;;
esac
