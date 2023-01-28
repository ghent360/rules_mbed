# -*- python -*-

# Copyright 2018-2019 Josh Pieper, jjp@pobox.com.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "patch")
load("//tools/workspace/mbed:json.bzl", "parse_json")


DEFAULT_CONFIG = {
    "CLOCK_SOURCE": "USE_PLL_HSE_EXTC|USE_PLL_HSI",
    "LPTICKER_DELAY_TICKS": "1",
    "MBED_CONF_DRIVERS_UART_SERIAL_RXBUF_SIZE": "256",
    "MBED_CONF_DRIVERS_UART_SERIAL_TXBUF_SIZE": "256",
    "MBED_CONF_EVENTS_SHARED_DISPATCH_FROM_APPLICATION": "1",
    "MBED_CONF_EVENTS_SHARED_EVENTSIZE": "256",
    "MBED_CONF_EVENTS_SHARED_HIGHPRIO_EVENTSIZE": "256",
    "MBED_CONF_EVENTS_SHARED_HIGHPRIO_STACKSIZE": "1024",
    "MBED_CONF_EVENTS_SHARED_STACKSIZE": "1024",
    "MBED_CONF_EVENTS_USE_LOWPOWER_TIMER_TICKER": "0",
    "MBED_CONF_PLATFORM_CTHUNK_COUNT_MAX": "4",
    "MBED_CONF_PLATFORM_DEFAULT_SERIAL_BAUD_RATE": "9600",
    "MBED_CONF_PLATFORM_ERROR_ALL_THREADS_INFO": "0",
    "MBED_CONF_PLATFORM_ERROR_DECODE_HTTP_URL_STR": r'"%d"',
    "MBED_CONF_PLATFORM_ERROR_FILENAME_CAPTURE_ENABLED": "0",
    "MBED_CONF_PLATFORM_ERROR_HIST_ENABLED": "0",
    "MBED_CONF_PLATFORM_ERROR_HIST_SIZE": "4",
    "MBED_CONF_PLATFORM_FORCE_NON_COPYABLE_ERROR": "0",
    "MBED_CONF_PLATFORM_MAX_ERROR_FILENAME_LEN": "16",
    "MBED_CONF_PLATFORM_POLL_USE_LOWPOWER_TIMER": "0",
    "MBED_CONF_PLATFORM_STDIO_BAUD_RATE": "9600",
    "MBED_CONF_PLATFORM_STDIO_BUFFERED_SERIAL": "0",
    "MBED_CONF_PLATFORM_STDIO_CONVERT_NEWLINES": "0",
    "MBED_CONF_PLATFORM_STDIO_FLUSH_AT_EXIT": "1",
    "MBED_CONF_RTOS_IDLE_THREAD_STACK_SIZE": "512",
    "MBED_CONF_RTOS_MAIN_THREAD_STACK_SIZE": "4096",
    "MBED_CONF_RTOS_PRESENT" : "true",
    "MBED_CONF_RTOS_THREAD_STACK_SIZE": "4096",
    "MBED_CONF_RTOS_TIMER_THREAD_STACK_SIZE": "768",
    "MBED_CONF_TARGET_LPUART_CLOCK_SOURCE": "USE_LPUART_CLK_LSE|USE_LPUART_CLK_PCLK1",
    "MBED_CONF_TARGET_LSE_AVAILABLE": "1",
    "MBED_CONF_TARGET_RTC_CLOCK_SOURCE": "USE_RTC_CLK_LSI",
    "MBED_CONF_TARGET_DEEP_SLEEP_LATENCY": "0",
    "MBED_CONF_TARGET_DEFAULT_ADC_VREF": "3.3f",
    "MBED_CONF_TARGET_I2C_TIMING_VALUE_ALGO": "0",
    "MBED_CRC_TABLE_SIZE": "16",
    "MEM_ALLOC": "malloc",
    "MEM_FREE": "free",
}


def _escape(item):
    return item.replace('"', r'\\\"')


def _render_list(data):
    result = "[\n"
    for item in data:
        result += ' "{}",\n'.format(_escape(item))
    result += "]\n"
    return result


def _get_target_defines(repository_ctx, target_path):
    target_name = target_path.rsplit('/', 1)[1]
    if not target_name.startswith("TARGET_"):
        fail("Final target directory does not start with TARGET_")

    first_target = target_name.split("TARGET_")[1]

    targets_results = repository_ctx.execute(["cat", "targets/targets.json"])
    if targets_results.return_code != 0:
        fail("error reading targets.json")

    targets = parse_json(targets_results.stdout)

    to_query = [first_target]

    # This aggregation would be natural to do recursively.  However,
    # Starlark of course does not support that.  Thus, we'll just
    # emulate the recursion with a local stack that we collapse at the
    # end.

    # Contains length 2 lists, where the first element are things to
    # add, and the second element are things to remove.
    stack = []

    for i in range(100):
        if len(to_query) == 0:
            break

        target = to_query[0]
        to_query = to_query[1:]

        if target not in targets:
            fail("Could not find '{}' in targets.json".format(target))

        stack = stack + [[[], []]]
        this_stack = stack[-1]

        this_stack[0] += ["TARGET_{}".format(target)]

        item = targets[target]

        this_stack[0] += ["DEVICE_{}".format(x) for x in item.get("device_has", [])]
        this_stack[0] += ["DEVICE_{}".format(x) for x in item.get("device_has_add", [])]
        this_stack[1] += ["DEVICE_{}".format(x) for x in item.get("device_has_remove", [])]

        this_stack[0] += ["TARGET_{}".format(x) for x in item.get("extra_labels", [])]
        this_stack[0] += ["TARGET_{}".format(x) for x in item.get("extra_labels_add", [])]
        this_stack[1] += ["TARGET_{}".format(x) for x in item.get("extra_labels_remove", [])]

        if "device_name" in item:
            this_stack[0] += ["TARGET_{}".format(item["device_name"])]

        if "core" in item:
            core = item.get("core")
            if core == 'Cortex-M4F' or core == 'Cortex-M4':
                this_stack[0] += [
                    "ARM_MATH_CM4",
                    "__CORTEX_M4",
                    "TARGET_RTOS_M4_M7",
                    "TARGET_LIKE_CORTEX_M4",
                    "TARGET_M4",
                    "TARGET_CORTEX_M",
                    "TARGET_CORTEX",
                ]
            elif core == 'Cortex-M3':
                this_stack[0] += [
                    "ARM_MATH_CM3",
                    "__CORTEX_M3",
                    "TARGET_LIKE_CORTEX_M3",
                    "TARGET_M3",
                    "TARGET_CORTEX_M",
                    "TARGET_CORTEX",
                ]
            elif core == 'Cortex-M0+':
                this_stack[0] += [
                    "ARM_MATH_CM0PLUS",
                    "__CORTEX_M0PLUS",
                    "TARGET_M0P",
                    "TARGET_CORTEX_M",
                    "TARGET_CORTEX",
                ]
            elif core == 'Cortex-M0':
                this_stack[0] += [
                    "ARM_MATH_CM0",
                    "__CORTEX_M0",
                    "TARGET_LIKE_CORTEX_M0",
                    "TARGET_M0",
                    "TARGET_CORTEX_M",
                    "TARGET_CORTEX",
                ]
            elif core != None:
                fail("Unknown core:" + core)


        this_stack[0] += item.get("macros", [])
        this_stack[0] += item.get("macros_add", [])
        this_stack[1] += item.get("macros_remove", [])

        this_stack[0] += ["TARGET_FF_{}".format(x) for x in item.get("supported_form_factors", [])]

        to_query += item.get("inherits", [])

    result = {}
    for to_add, to_remove in reversed(stack):
        for item in to_add:
            result[item] = None
        for item in to_remove:
            result.pop(item)

    # I have no clue what this is, but we don't support it.
    if "TARGET_PSA" in result:
        result.pop("TARGET_PSA")

    return sorted(result.keys())

def _impl(repository_ctx):
    PREFIX = "external/{}".format(repository_ctx.name)

    repository_ctx.download_and_extract(
        url = [
            "https://github.com/ARMmbed/mbed-os/archive/mbed-os-6.16.0.tar.gz",
        ],
        sha256 = "eebf04e6badd3a263d857b585718f0a282d16d01e24a1d88f247c76d1227150b",
        stripPrefix = "mbed-os-mbed-os-6.16.0",
    )
    patch(repository_ctx)


    my_config = {}
    # It is annoying that bazel does not give us full featured dicts.
    for key, value in DEFAULT_CONFIG.items():
        my_config[key] = value
    for key, value in repository_ctx.attr.config.items():
        my_config[key] = value


    # Since mbed is full of circular dependencies, we just construct
    # the full set of headers and sources here, then pass it down into
    # the BUILD file verbatim for using in a single bazel label.

    target = repository_ctx.attr.target

    defines = ["{}={}".format(key, value)
               for key, value in my_config.items()
               if value != "<undefined>"]

    defines += _get_target_defines(repository_ctx, target)

    for key, value in my_config.items():
        if value != "<undefined>":
            continue

        if key in defines:
            defines.remove(key)

    hdr_globs = [
        "mbed.h",
        "platform/cxxsupport/*",
        "platform/source/*.h",
        "platform/include/platform/*.h",
        "platform/include/platform/internal/*.h",
        "drivers/include/drivers/*.h",
        "drivers/include/drivers/interfaces/*.h",
        "cmsis/CMSIS_5/CMSIS/TARGET_CORTEX_M/Include/*.h",
        "events/include/events/*.h",
        "hal/include/hal/*.h",
    ]

    enable_rtos = my_config["MBED_CONF_RTOS_PRESENT"] != "<undefined>"

    if enable_rtos:
        hdr_globs += [
            "rtos/*.h",
            "rtos/TARGET_CORTEX/**/*.h",
        ]

    src_globs = [
        "platform/source/*.c",
        "platform/source/TARGET_CORTEX_M/*.c",
        "platform/source/*.cpp",
        "drivers/source/*.cpp",
        "cmsis/CMSIS_5/CMSIS/TARGET_CORTEX_M/Source/*.c",
        "hal/source/*.c",
        "hal/source/*.cpp",
    ]

    if enable_rtos:
        src_globs += [
            "events/*.cpp",
            "events/equeue/equeue.c",
            "events/equeue/equeue_mbed.cpp",
            "rtos/TARGET_CORTEX/*.c",
            "rtos/TARGET_CORTEX/*.cpp",
            "rtos/TARGET_CORTEX/rtx5/RTX/Source/*.c",
            "rtos/TARGET_CORTEX/rtx5/Source/*.c",
            "rtos/TARGET_CORTEX/TOOLCHAIN_GCC_ARM/*.c",
            "rtos/*.cpp",
        ]
        if "TARGET_M4" in defines:
            src_globs += [
                "rtos/TARGET_CORTEX/rtx5/RTX/Source/TOOLCHAIN_GCC/TARGET_RTOS_M4_M7/*.S",
            ]
        elif "TARGET_M3" in defines:
            src_globs += [
                "rtos/TARGET_CORTEX/rtx5/RTX/Source/TOOLCHAIN_GCC/TARGET_RTOS_M3/*.S",
            ]
        elif "TARGET_M0P" in defines:
            src_globs += [
                "rtos/TARGET_CORTEX/rtx5/RTX/Source/TOOLCHAIN_GCC/TARGET_RTOS_M0P/*.S",
            ]
        elif "TARGET_M0" in defines:
            src_globs += [
                "rtos/TARGET_CORTEX/rtx5/RTX/Source/TOOLCHAIN_GCC/TARGET_RTOS_M0/*.S",
            ]
        else:
            fail("Unknown core")


    includes = [
        ".",
        "platform/cxxsupport",
        "platform/source",
        "platform/include",
        "platform/include/platform",
        "platform/include/platform/internal",
        "drivers/include",
        "drivers/include/drivers",
        "cmsis/CMSIS_5/CMSIS/TARGET_CORTEX_M/Include",
        "hal/include",
        "hal/include/hal",
    ]

    if enable_rtos:
        includes += [
            "events",
            "rtos".format(PREFIX),
            "rtos/TARGET_CORTEX",
            "rtos/TARGET_CORTEX/rtx4",
            "rtos/TARGET_CORTEX/rtx5/Include",
            "rtos/TARGET_CORTEX/rtx5/Source",
            "rtos/TARGET_CORTEX/rtx5/RTX/Include",
            "rtos/TARGET_CORTEX/rtx5/RTX/Source",
            "rtos/TARGET_CORTEX/rtx5/RTX/Config",
        ]

    copts = [
        "-Wno-unused-parameter",
        "-Wno-missing-field-initializers",
        "-Wno-register",
        "-Wno-deprecated-declarations",
        "-Wno-sized-deallocation",
        "-Wno-shift-negative-value",
    ]

    linker_script = ""

    # Walk up the target path adding directories as we go.
    remaining_target = target

    # This would naturally be expressed as a 'while' loop.  Instead
    # we'll just encode a maximum size that is way more than enough.
    # Go Starlark.
    for i in range(1000):
        cube_fw = "{}/STM32Cube_FW".format(remaining_target)
        if repository_ctx.path(cube_fw).exists:
            hdr_globs += [
                "{}/*.h".format(cube_fw),
                "{}/CMSIS/*.h".format(cube_fw),
            ]
            includes += [
                cube_fw,
                "{}/CMSIS".format(cube_fw),
            ]
            find_result = repository_ctx.execute(["find", cube_fw, '-type', 'd', '-name', 'STM32*xx_HAL_Driver'])
            if find_result.return_code == 0 and len(find_result.stdout) > 0:
                hal_driver = find_result.stdout.strip()
                includes += [
                    hal_driver,
                    "{}/Legacy".format(hal_driver),
                ]
                hdr_globs += [
                    "{}/*.h".format(hal_driver),
                    "{}/Legacy/*.h".format(hal_driver),
                ]
                src_globs += [
                    "{}/*.c".format(hal_driver),
                ]

        hdr_globs += [
            "{}/*.h".format(remaining_target),
        ]
        src_globs += [
            "{}/*.c".format(remaining_target),
            "{}/*.cpp".format(remaining_target),
        ]
        includes += [
            remaining_target,
            "{}/TOOLCHAIN_GCC_ARM".format(remaining_target),
        ]

        device = repository_ctx.path("{}/device".format(remaining_target))
        if device.exists:
            hdr_globs += [
                "{}/device/*.h".format(remaining_target),
            ]
            src_globs += [
                "{}/device/*.c".format(remaining_target),
                "{}/device/TOOLCHAIN_GCC_ARM/*.S".format(remaining_target),
            ]
            includes += [
                "{}/device".format(remaining_target),
            ]

        # Does this directory contain the linker script?

        linker_search_path = "{}/TOOLCHAIN_GCC_ARM/".format(remaining_target)
        find_result = repository_ctx.execute(["find", linker_search_path, '-name', '*.ld'])
        if find_result.return_code == 0 and len(find_result.stdout) > 0:
            linker_script = find_result.stdout.strip()
            linker_deps = "{}/cmsis_nvic.h".format(remaining_target)

        items = remaining_target.rsplit('/', 1)
        if len(items) == 1:
            break

        remaining_target = items[0]

    if linker_script == "":
        fail("Could not find linker script")


    substitutions = {
        '@HDR_GLOBS@': _render_list(hdr_globs),
        '@SRC_GLOBS@': _render_list(src_globs),
        '@INCLUDES@': _render_list(includes),
        '@COPTS@': _render_list(copts),
        '@DEFINES@': _render_list(defines),
        '@LINKER_SCRIPT@': _escape(linker_script),
        '@LINKER_DEPS@': _escape(linker_deps),
    }

    repository_ctx.template(
        'rules.bzl',
        repository_ctx.attr.rules_file,
    )

    repository_ctx.template(
        'BUILD',
        repository_ctx.attr.build_file_template,
        substitutions = substitutions,
    )

    # repository_ctx.symlink(linker_script, "linker_script.ld.in")

_mbed_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "build_file_template" : attr.label(allow_single_file = True),
        "rules_file" : attr.label(allow_single_file = True),
        "target" : attr.string(),
        "config" : attr.string_dict(),
        "patches": attr.label_list(default = []),
        "patch_tool": attr.string(default = "patch"),
        "patch_args": attr.string_list(default = ["-p0"]),
        "patch_cmds": attr.string_list(default = []),
    }
)

def mbed_repository(
        name,
        target,
        config = None):

    _mbed_repository(
        name = name,
        build_file_template = Label("//tools/workspace/mbed:package.BUILD"),
        rules_file = Label("//tools/workspace/mbed:rules.bzl"),
        target = target,
        config = config or DEFAULT_CONFIG,
        patches = [
        ],
        patch_args = ["-p1"],
    )
