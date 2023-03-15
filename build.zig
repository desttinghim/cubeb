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
    } else {
        cubeb.linkSystemLibrary("speex");
    }

    // TODO implement lazy load libs logic

    const use_pulse = b.option(bool, "use-pulse", "Use pulse audio") orelse true;
    cubeb.defineCMacro("USE_PULSE", if (use_pulse) "1" else null);
    if (use_pulse) {
        cubeb.linkSystemLibrary("pulse");
        cubeb.addCSourceFile("src/cubeb_pulse.c", &.{});
    }

    const use_alsa = b.option(bool, "use-alsa", "Use alsa audio") orelse true;
    cubeb.defineCMacro("USE_ALSA", if (use_alsa) "1" else null);
    if (use_alsa) {
        cubeb.addCSourceFile("src/cubeb_alsa.c", &.{});
    }

    const use_jack = b.option(bool, "use-jack", "Use jack audio") orelse true;
    cubeb.defineCMacro("USE_JACK", if (use_jack) "1" else null);
    if (use_jack) {
        cubeb.addCSourceFile("src/cubeb_jack.c", &.{});
    }

    const use_sndio = b.option(bool, "use-sndio", "Use sndio audio") orelse true;
    cubeb.defineCMacro("USE_SNDIO", if (use_sndio) "1" else null);
    if (use_sndio) {
        cubeb.addCSourceFile("src/cubeb_sndio.c", &.{});
    }

    const use_aaudio = b.option(bool, "use-aaudio", "Use aaudio audio") orelse false;
    cubeb.defineCMacro("USE_AAUDIO", if (use_aaudio) "1" else null);
    if (use_aaudio) {
        cubeb.addCSourceFile("src/cubeb_aaudio.c", &.{});
    }

    cubeb.installHeadersDirectory("include/cubeb", "cubeb");
}
