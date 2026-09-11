# 2026-09-11T18:23:15.890722300
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_udp")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../output/system.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

platform = client.get_component(name="platform")
status = platform.build()

domain = platform.get_domain(name="zynq_fsbl")

status = domain.set_lib(lib_name="lwip220", path="$COMPONENT_LOCATION/../../../../../Vivado/2025.2.1/data/embeddedsw/ThirdParty/sw_services/lwip220_v1_3")

status = platform.build()

comp = client.create_app_component(name="app_component",platform = "$COMPONENT_LOCATION/../platform/export/platform/platform.xpfm",domain = "standalone_ps7_cortexa9_0")

comp = client.get_component(name="app_component")
comp.build()

comp = client.get_component(name="app_component")
status = comp.import_files(from_loc="$COMPONENT_LOCATION/../../sw/ps", files=["main.c"], dest_dir_in_cmp = "src", is_skip_copy_sources = False)

comp = client.get_component(name="app_component")
status = comp.clean()

status = comp.clean()

status = platform.build()

comp.build()

vitis.dispose()

vitis.dispose()

