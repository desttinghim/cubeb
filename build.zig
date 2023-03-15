const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const export_header = b.addConfigHeader(.{
        .style = .blank,
        .max_bytes = 4096,
        .include_path = "cubeb_export.h",
    }, .{
        .CUBEB_EXPORT = {},
        .CUBEB_NO_EXPORT = {},
        .CUBEB_DEPRECATED = "__attribute__ ((__deprecated__))",
    });
    b.getInstallStep().dependOn(&export_header.step);

    const cubeb = b.addStaticLibrary(.{
        .name = "cubeb",
        .target = target,
        .optimize = optimize,
    });
    cubeb.install();
    cubeb.step.dependOn(&export_header.step);
    cubeb.addConfigHeader(export_header);
    cubeb.installConfigHeader(export_header, .{ .install_dir = .{ .custom = "exports" } });
    cubeb.linkLibC();
    cubeb.linkLibCpp();
    cubeb.disable_sanitize_c = true;
    cubeb.addIncludePath("include");
    cubeb.addCSourceFiles(&.{
        "src/cubeb.c",
        "src/cubeb_mixer.cpp",
        "src/cubeb_resampler.cpp",
        "src/cubeb_log.cpp",
        "src/cubeb_strings.c",
        "src/cubeb_utils.cpp",
    }, &.{});

    const bundle_speex = b.option(bool, "BUNDLE_SPEEX", "Bundle speex resampler") orelse true;

    if (bundle_speex) {
        const speex = b.addStaticLibrary(.{
            .name = "speex",
            .target = target,
            .optimize = optimize,
        });
        speex.step.dependOn(&export_header.step);
        speex.install();
        speex.force_pic = true;
        speex.disable_sanitize_c = true;
        speex.linkLibC();
        speex.defineCMacro("OUTSIDE_SPEEX", "");
        speex.defineCMacro("FLOATING_POINT", "");
        speex.defineCMacro("EXPORT", "");
        speex.defineCMacro("RANDOM_PREFIX", "speex");
        speex.addCSourceFiles(&.{
            "subprojects/speex/resample.c",
        }, &.{});

        cubeb.defineCMacro("OUTSIDE_SPEEX", "");
        cubeb.defineCMacro("FLOATING_POINT", "");
        cubeb.defineCMacro("EXPORT", "");
        cubeb.defineCMacro("RANDOM_PREFIX", "speex");
        cubeb.linkLibrary(speex);
        cubeb.addIncludePath("subprojects");
        cubeb.step.dependOn(&speex.step);
    } else {
        cubeb.linkSystemLibrary("speex");
    }

    // TODO implement lazy load libs logic
    const Opt = struct {
        use_pulse: bool = false,
        use_alsa: bool = false,
        use_jack: bool = false,
        use_sndio: bool = false,
        use_aaudio: bool = false,
        use_audiounit: bool = false,
        use_wasapi: bool = false,
        use_winmm: bool = false,
        use_opensl: bool = false,
        use_sys_soundcard: bool = false,
        use_audiotrack: bool = false,
        use_sun: bool = false,
        use_kai: bool = false,
    };
    const opt: Opt = opt: {
        switch (target.getOsTag()) {
            .linux => {
                if (target.getAbi() == .android) {
                    break :opt .{
                        .use_aaudio = b.option(bool, "USE_AAUDIO", "Use AAudio backend") orelse true,
                        .use_opensl = b.option(bool, "USE_OPENSSL", "Use OpenSL backend") orelse true,
                    };
                }
                break :opt .{
                    .use_pulse = b.option(bool, "USE_PULSE", "Use Pulse Audio backend") orelse true,
                    .use_alsa = b.option(bool, "USE_ALSA", "Use Alsa backend") orelse true,
                    .use_jack = b.option(bool, "USE_JACK", "Use Jack backend") orelse true,
                };
            },
            .windows => {
                break :opt .{
                    .use_wasapi = b.option(bool, "USE_WASAPI", "Use WASAPI backend") orelse true,
                    .use_winmm = b.option(bool, "USE_WINMM", "Use winmm backend") orelse true,
                };
            },
            .macos => {
                break :opt .{
                    .use_audiounit = b.option(bool, "USE_AUDIOUNIT", "Use AudioUnit backend") orelse true,
                };
            },
            inline else => |t| {
                std.log.err("Unsupported platform {s}", .{@tagName(t)});
            },
        }
    };

    if (opt.use_pulse) {
        cubeb.defineCMacro("USE_PULSE", if (opt.use_pulse) "1" else null);
        cubeb.linkSystemLibrary("pulse");
        cubeb.addCSourceFile("src/cubeb_pulse.c", &.{});
    }

    if (opt.use_alsa) {
        cubeb.defineCMacro("USE_ALSA", if (opt.use_alsa) "1" else null);
        cubeb.addCSourceFile("src/cubeb_alsa.c", &.{});
    }

    if (opt.use_jack) {
        cubeb.defineCMacro("USE_JACK", if (opt.use_jack) "1" else null);
        cubeb.addCSourceFile("src/cubeb_jack.cpp", &.{});
    }

    if (opt.use_sndio) {
        cubeb.defineCMacro("USE_SNDIO", if (opt.use_sndio) "1" else null);
        cubeb.addCSourceFile("src/cubeb_sndio.c", &.{});
    }

    const aaudio_low_latency = b.option(bool, "CUBEB_AAUDIO_LOW_LATENCY", "Use low latency") orelse false;
    if (opt.use_aaudio) {
        cubeb.defineCMacro("USE_AAUDIO", if (opt.use_aaudio) "1" else null);
        cubeb.defineCMacro("CUBEB_AAUDIO_LOW_LATENCY", if (aaudio_low_latency) "1" else null);
        cubeb.addCSourceFile("src/cubeb_aaudio.cpp", &.{});
    }

    if (opt.use_audiounit) {
        cubeb.defineCMacro("use_audiounit", if (opt.use_audiounit) "1" else null);
        cubeb.addCSourceFile("src/cubeb_audiounit.cpp", &.{});
        cubeb.addCSourceFile("src/cubeb_osx_run_loop.cpp", &.{});
        cubeb.linkFramework("AudioUnit");
        cubeb.linkFramework("CoreAudio");
        cubeb.linkFramework("CoreServices");
    }

    if (opt.use_wasapi) {
        cubeb.defineCMacro("USE_WASAPI", if (opt.use_wasapi) "1" else null);
        cubeb.addCSourceFile("src/cubeb_wasapi.c", &.{});
        cubeb.linkSystemLibrary("avrt");
        cubeb.linkSystemLibrary("ole32");
        cubeb.linkSystemLibrary("ksuser");
    }

    if (opt.use_winmm) {
        cubeb.defineCMacro("USE_WINMM", if (opt.use_winmm) "1" else null);
        cubeb.addCSourceFile("src/cubeb_winmm.c", &.{});
        cubeb.linkSystemLibrary("winmm");
    }

    if (opt.use_opensl) {
        cubeb.defineCMacro("USE_OPENSL", if (opt.use_opensl) "1" else null);
        cubeb.addCSourceFile("src/cubeb_opensl.c", &.{});
        cubeb.addCSourceFile("src/cubeb-jni.cpp", &.{});
        cubeb.linkSystemLibrary("OpenSLES");
    }

    // cubeb.defineCMacro("USE_OSS", if (opt.use_oss) "1" else null);
    // if (opt.use_oss) {
    //     cubeb.addCSourceFile("src/cubeb_oss.c", &.{});
    //     cubeb.linkSystemLibrary("oss");
    // }

    if (opt.use_sun) {
        cubeb.defineCMacro("USE_SUN", if (opt.use_sun) "1" else null);
        cubeb.addCSourceFile("src/cubeb_sun.c", &.{});
    }

    if (opt.use_kai) {
        cubeb.defineCMacro("USE_KAI", if (opt.use_kai) "1" else null);
        cubeb.addCSourceFile("src/cubeb_kai.c", &.{});
        cubeb.linkSystemLibrary("kai");
    }

    cubeb.installHeadersDirectory("include/cubeb", "cubeb");
}
