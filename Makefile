DEBUG=0
FORCE_GLES=1
FORCE_GLES3=0
LLE=1

DYNAFLAGS :=
INCFLAGS  :=
COREFLAGS :=
CPUFLAGS  :=
GLFLAGS   :=

UNAME=$(shell uname -a)

# Dirs
ROOT_DIR := .
LIBRETRO_DIR := $(ROOT_DIR)/libretro

ifeq ($(platform),)
   platform = unix
   ifeq ($(UNAME),)
      platform = win
   else ifneq ($(findstring MINGW,$(UNAME)),)
      platform = win
   else ifneq ($(findstring Darwin,$(UNAME)),)
      platform = osx
   else ifneq ($(findstring win,$(UNAME)),)
      platform = win
   endif
else ifneq (,$(findstring armv,$(platform)))
    ifeq (,$(findstring classic_,$(platform)))
        override platform += unix
    endif
endif

# system platform
system_platform = unix
ifeq ($(shell uname -a),)
   EXE_EXT = .exe
   system_platform = win
else ifneq ($(findstring Darwin,$(shell uname -a)),)
   system_platform = osx
   arch = intel
ifeq ($(shell uname -p),powerpc)
   arch = ppc
endif
else ifneq ($(findstring MINGW,$(shell uname -a)),)
   system_platform = win
endif

# Cross compile?
ifeq (,$(ARCH))
   ARCH = $(shell uname -m)
endif

# Target Dynarec
WITH_DYNAREC = $(ARCH)

PIC = 1
ifeq ($(ARCH), $(filter $(ARCH), i386 i686))
   WITH_DYNAREC = x86
   PIC = 0
else ifeq ($(ARCH), $(filter $(ARCH), arm))
   WITH_DYNAREC = arm
else ifeq ($(ARCH), $(filter $(ARCH), aarch64))
   WITH_DYNAREC = aarch64
endif

TARGET_NAME := km_ludicrousn64_2k22_xtreme_amped
CC_AS ?= $(CC)

GIT_VERSION ?= " $(shell git rev-parse --short HEAD || echo unknown)"
ifneq ($(GIT_VERSION)," unknown")
	COREFLAGS += -DGIT_VERSION=\"$(GIT_VERSION)\"
endif

# Linux
ifneq (,$(findstring unix,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.so
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined

   ifeq ($(FORCE_GLES),1)
      GLES = 1
      GL_LIB := -lGLESv2
   else ifeq ($(FORCE_GLES3),1)
      GLES3 = 1
      GL_LIB := -lGLESv2
   else
      GL_LIB := -lGL
   endif

   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE
# Raspberry Pi
else ifneq (,$(findstring rpi,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.so
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined
   GLES = 1
   ifneq (,$(findstring mesa,$(platform)))
      GL_LIB := -lGLESv2
   else
      LLE = 0
      CPUFLAGS += -DVC
      GL_LIB := -L/opt/vc/lib -lbrcmGLESv2
      EGL_LIB := -lbrcmEGL
      INCFLAGS += -I/opt/vc/include -I/opt/vc/include/interface/vcos -I/opt/vc/include/interface/vcos/pthreads
   endif
   WITH_DYNAREC=arm
   ifneq (,$(findstring rpi2,$(platform)))
      CPUFLAGS += -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -DVC
      HAVE_NEON = 1
   else ifneq (,$(findstring rpi3,$(platform)))
      CPUFLAGS += -march=armv8-a+crc -mtune=cortex-a53
      HAVE_NEON = 1
   else ifneq (,$(findstring rpi4,$(platform)))
      CPUFLAGS += -march=armv8-a+crc -mtune=cortex-a72 -mfpu=neon-fp-armv8 -mfloat-abi=hard
      HAVE_NEON = 1
   endif
   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE

# Classic Platforms ####################
# Platform affix = classic_<ISA>_<µARCH>
# Help at https://modmyclassic.com/comp

# (armv7 a7, hard point, neon based) ### 
# NESC, SNESC, C64 mini 
else ifeq ($(platform), classic_armv7_a7)
	TARGET := $(TARGET_NAME)_libretro.so
	LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined
	GLES = 1
	GL_LIB := -lGLESv2
	fpic := -fPIC
	CPUFLAGS += -Ofast \
	-flto=4 -fwhole-program -fuse-linker-plugin \
	-fdata-sections -ffunction-sections -Wl,--gc-sections \
	-fno-stack-protector -fno-ident -fomit-frame-pointer \
	-falign-functions=1 -falign-jumps=1 -falign-loops=1 \
	-fno-unwind-tables -fno-asynchronous-unwind-tables -fno-unroll-loops \
	-fmerge-all-constants -fno-math-errno \
	-marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
	HAVE_NEON = 1
	WITH_DYNAREC=arm
	COREFLAGS += -DOS_LINUX
	ASFLAGS = -f elf -d ELF_TYPE
	LDFLAGS += -marm -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard
	#This fixes the config for MALI based devices...
	CPUFLAGS += -DCLASSIC
	ifeq ($(shell echo `$(CC) -dumpversion` "< 4.9" | bc -l), 1)
	  CFLAGS += -march=armv7-a
	else
	  CFLAGS += -march=armv7ve
	  # If gcc is 5.0 or later
	  ifeq ($(shell echo `$(CC) -dumpversion` ">= 5" | bc -l), 1)
	    LDFLAGS += -static-libgcc -static-libstdc++
	  endif
	endif
#######################################

# Nintendo Switch
else ifeq ($(platform), libnx)
   include $(DEVKITPRO)/libnx/switch_rules
   PIC ?= 1
   WITH_DYNAREC := aarch64
   TARGET := $(TARGET_NAME)_libretro_$(platform).a
   CPUOPTS := -g -march=armv8-a -mtune=cortex-a57 -mtp=soft -mcpu=cortex-a57+crc+fp+simd
   PLATCFLAGS = -O3 -I$(PORTLIBS)/include/ -I$(LIBNX)/include/ -ffunction-sections -fdata-sections -ftls-model=local-exec -specs=$(LIBNX)/switch.specs
   PLATCFLAGS += $(INCLUDE) -D__SWITCH__=1 -DSWITCH -DHAVE_LIBNX -D_GLIBCXX_USE_C99_MATH_TR1 -D_LDBL_EQ_DBL -funroll-loops
   CXXFLAGS += -fno-rtti -std=gnu++11
   COREFLAGS += -DOS_LINUX -DUSE_DEPTH_RENDERBUFFER
   GLES = 0
   STATIC_LINKING = 1

# 64 bit ODROIDs
else ifneq (,$(findstring odroid64,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.so
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined
   BOARD := $(shell cat /proc/cpuinfo | grep -i odroid | awk '{print $$3}')
   GLES = 1
   GL_LIB := -lGLESv2
   WITH_DYNAREC := aarch64
   ifneq (,$(findstring C2,$(BOARD)))
      # ODROID-C2
      CPUFLAGS += -mcpu=cortex-a53
   else ifneq (,$(findstring N1,$(BOARD)))
      # ODROID-N1
      CPUFLAGS += -mcpu=cortex-a72.cortex-a53
   else ifneq (,$(findstring N2,$(BOARD)))
      # ODROID-N2
      CPUFLAGS += -mcpu=cortex-a73.cortex-a53
   endif

   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE   

# ODROIDs
else ifneq (,$(findstring odroid,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.so
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined
   BOARD := $(shell cat /proc/cpuinfo | grep -i odroid | awk '{print $$3}')
   GLES = 1
   GL_LIB := -lGLESv2
   CPUFLAGS += -marm -mfloat-abi=hard -mfpu=neon
   HAVE_NEON = 1
   WITH_DYNAREC=arm
   ifneq (,$(findstring ODROIDC,$(BOARD)))
      # ODROID-C1
      CPUFLAGS += -mcpu=cortex-a5
   else ifneq (,$(findstring ODROID-XU,$(BOARD)))
      # ODROID-XU3 & -XU3 Lite and -XU4
      ifeq "$(shell expr `gcc -dumpversion` \>= 4.9)" "1"
         CPUFLAGS += -march=armv7ve -mcpu=cortex-a15.cortex-a7
      else
         CPUFLAGS += -mcpu=cortex-a9
      endif
   else
      # ODROID-U2, -U3, -X & -X2
      CPUFLAGS += -mcpu=cortex-a9
   endif

   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE
# OS X
else ifneq (,$(findstring osx,$(platform)))
   TARGET := $(TARGET_NAME)_libretro.dylib
   LDFLAGS += -dynamiclib
   OSXVER = `sw_vers -productVersion | cut -d. -f 2`
   OSX_LT_MAVERICKS = `(( $(OSXVER) <= 9)) && echo "YES"`
        LDFLAGS += -mmacosx-version-min=10.7
   LDFLAGS += -stdlib=libc++

   PLATCFLAGS += -D__MACOSX__ -DOSX -DOS_MAC_OS_X
   GL_LIB := -framework OpenGL

   # Target Dynarec
   ifeq ($(ARCH), $(filter $(ARCH), ppc))
      WITH_DYNAREC =
   endif

   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE
# iOS
else ifneq (,$(findstring ios,$(platform)))
   ifeq ($(IOSSDK),)
      IOSSDK := $(shell xcodebuild -version -sdk iphoneos Path)
   endif

   TARGET := $(TARGET_NAME)_libretro_ios.dylib
   DEFINES += -DIOS
   GLES = 1
   WITH_DYNAREC=arm

   PLATCFLAGS += -DOS_MAC_OS_X
   PLATCFLAGS += -DHAVE_POSIX_MEMALIGN -DNO_ASM
   PLATCFLAGS += -DIOS -marm
   CPUFLAGS += -DNO_ASM  -DARM -D__arm__ -DARM_ASM -D__NEON_OPT
   CPUFLAGS += -marm -mcpu=cortex-a8 -mfpu=neon -mfloat-abi=softfp
   LDFLAGS += -dynamiclib
   HAVE_NEON=1

   GL_LIB := -framework OpenGLES

   CC = clang -arch armv7 -isysroot $(IOSSDK)
   CC_AS = perl ./tools/gas-preprocessor.pl $(CC)
   CXX = clang++ -arch armv7 -isysroot $(IOSSDK)
   ifeq ($(platform),ios9)
      CC         += -miphoneos-version-min=8.0
      CC_AS      += -miphoneos-version-min=8.0
      CXX        += -miphoneos-version-min=8.0
      PLATCFLAGS += -miphoneos-version-min=8.0
   else
      CC += -miphoneos-version-min=5.0
      CC_AS += -miphoneos-version-min=5.0
      CXX += -miphoneos-version-min=5.0
      PLATCFLAGS += -miphoneos-version-min=5.0
   endif

   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE
# Android
else ifneq (,$(findstring android,$(platform)))
   LDFLAGS += -shared -Wl,--version-script=$(LIBRETRO_DIR)/link.T -Wl,--no-undefined -Wl,--warn-common -llog
   INCFLAGS += -I$(ROOT_DIR)/GLideN64/src/GLideNHQ/inc
   ifneq (,$(findstring x86,$(platform)))
      CC = i686-linux-android-gcc
      CXX = i686-linux-android-g++
      WITH_DYNAREC = x86
      LDFLAGS += -L$(ROOT_DIR)/custom/android/x86
   else
      CC = arm-linux-androideabi-gcc
      CXX = arm-linux-androideabi-g++
      WITH_DYNAREC = arm
      HAVE_NEON = 1
      CPUFLAGS += -march=armv7-a -mfloat-abi=softfp -mfpu=neon
      LDFLAGS += -march=armv7-a -L$(ROOT_DIR)/custom/android/arm
   endif
   ifneq (,$(findstring gles3,$(platform)))
      GL_LIB := -lGLESv3
      GLES3 = 1
      TARGET := $(TARGET_NAME)_gles3_libretro_android.so
   else
      GL_LIB := -lGLESv2
      GLES = 1
      TARGET := $(TARGET_NAME)_libretro_android.so
   endif
   CPUFLAGS += -DANDROID -DEGL_EGLEXT_PROTOTYPES

   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE
# emscripten
else ifeq ($(platform), emscripten)
   TARGET := $(TARGET_NAME)_libretro_emscripten.bc
   GLES := 1
   WITH_DYNAREC :=
   CPUFLAGS += -DEMSCRIPTEN -DNO_ASM -s USE_ZLIB=1
   PLATCFLAGS += \
      -Dsinc_resampler=glupen_sinc_resampler \
      -DCC_resampler=glupen_CC_resampler \
      -Drglgen_symbol_map=glupen_rglgen_symbol_map \
      -Drglgen_resolve_symbols_custom=glupen_rglgen_resolve_symbols_custom \
      -Drglgen_resolve_symbols=glupen_rglgen_resolve_symbols \
      -Dmemalign_alloc=glupen_memalign_alloc \
      -Dmemalign_free=glupen_memalign_free \
      -Dmemalign_alloc_aligned=glupen_memalign_alloc_aligned \
      -Daudio_resampler_driver_find_handle=glupen_audio_resampler_driver_find_handle \
      -Daudio_resampler_driver_find_ident=glupen_audio_resampler_driver_find_ident \
      -Drarch_resampler_realloc=glupen_rarch_resampler_realloc \
      -Dconvert_float_to_s16_C=glupen_convert_float_to_s16_C \
      -Dconvert_float_to_s16_init_simd=glupen_convert_float_to_s16_init_simd \
      -Dconvert_s16_to_float_C=glupen_convert_s16_to_float_C \
      -Dconvert_s16_to_float_init_simd=glupen_convert_s16_to_float_init_simd \
      -Dcpu_features_get_perf_counter=glupen_cpu_features_get_perf_counter \
      -Dcpu_features_get_time_usec=glupen_cpu_features_get_time_usec \
      -Dcpu_features_get_core_amount=glupen_cpu_features_get_core_amount \
      -Dcpu_features_get=glupen_cpu_features_get \
      -Dffs=glupen_ffs \
      -Dstrlcpy_retro__=glupen_strlcpy_retro__ \
      -Dstrlcat_retro__=glupen_strlcat_retro__
   CC = emcc
   CXX = em++
   HAVE_NEON = 0

   COREFLAGS += -DOS_LINUX
   ASFLAGS = -f elf -d ELF_TYPE
# Windows
else
   TARGET := $(TARGET_NAME)_libretro.dll
   LDFLAGS += -shared -static-libgcc -static-libstdc++ -Wl,--version-script=$(LIBRETRO_DIR)/link.T -lwinmm -lgdi32
   GL_LIB := -lopengl32
   ifneq (,$(findstring win32,$(platform)))
      CC = i686-w64-mingw32-gcc
      CXX = i686-w64-mingw32-g++
      WITH_DYNAREC = x86
   else ifneq (,$(findstring win64,$(platform)))
      CC = x86_64-w64-mingw32-gcc
      CXX = x86_64-w64-mingw32-g++
      WITH_DYNAREC = x86_64
   endif
	COREFLAGS += -DOS_WINDOWS -DMINGW
	ASFLAGS = -f win32
endif

ifeq ($(STATIC_LINKING), 1)
   ifneq (,$(findstring win,$(platform)))
      TARGET := $(TARGET:.dll=.lib)
   else ifneq ($(platform), $(filter $(platform), osx ios))
      TARGET := $(TARGET:.dylib=.a)            
   else
      TARGET := $(TARGET:.so=.a)
   endif
endif

include Makefile.common

ifeq ($(HAVE_NEON), 1)
   COREFLAGS += -DHAVE_NEON -D__ARM_NEON__ -D__NEON_OPT -ftree-vectorize -ftree-vectorizer-verbose=2 -funsafe-math-optimizations -fno-finite-math-only
endif

COREFLAGS += -D__LIBRETRO__ -DUSE_FILE32API -DM64P_PLUGIN_API -DM64P_CORE_PROTOTYPES -D_ENDUSER_RELEASE -DSINC_LOWER_QUALITY -DTXFILTER_LIB -D__VEC4_OPT -DMUPENPLUSAPI

ifeq ($(DEBUG), 1)
   CPUOPTS += -O0 -g
   CPUOPTS += -DOPENGL_DEBUG
else
   CPUOPTS += -DNDEBUG -fsigned-char -ffast-math -fno-strict-aliasing -fomit-frame-pointer -fvisibility=hidden
ifneq ($(platform), libnx)
   CPUOPTS := -Ofast $(CPUOPTS)
endif
   CXXFLAGS += -fvisibility-inlines-hidden
endif

ifneq ($(platform), libnx)
CXXFLAGS += -std=c++11
endif

ifeq ($(PIC), 1)
   fpic = -fPIC
else
   fpic = -fno-PIC
endif

OBJECTS     += $(SOURCES_CXX:.cpp=.o) $(SOURCES_C:.c=.o) $(SOURCES_ASM:.S=.o) $(SOURCES_NASM:.asm=.o)
CXXFLAGS    += $(CPUOPTS) $(COREFLAGS) $(INCFLAGS) $(PLATCFLAGS) $(fpic) $(CPUFLAGS) $(GLFLAGS) $(DYNAFLAGS)
CFLAGS      += $(CPUOPTS) $(COREFLAGS) $(INCFLAGS) $(PLATCFLAGS) $(fpic) $(CPUFLAGS) $(GLFLAGS) $(DYNAFLAGS)

ifeq (,$(findstring android,$(platform)))
   LDFLAGS    += -lpthread
endif

LDFLAGS    += $(fpic) -Ofast -lz

all: $(TARGET)
$(TARGET): $(OBJECTS)
ifeq ($(STATIC_LINKING), 1)
	$(AR) rcs $@ $(OBJECTS)
else
	$(CXX) -o $@ $(OBJECTS) $(LDFLAGS) $(GL_LIB)
endif

%.o: %.asm
	nasm $(ASFLAGS) $< -o $@

%.o: %.S
	$(CC_AS) $(CFLAGS) -c $< -o $@

%.o: %.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

%.o: %.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@


clean:
	find -name "*.o" -type f -delete
	find -name "*.d" -type f -delete
	rm -f $(TARGET)

.PHONY: clean
-include $(OBJECTS:.o=.d)
