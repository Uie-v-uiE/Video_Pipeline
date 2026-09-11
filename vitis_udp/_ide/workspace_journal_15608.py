# 2026-09-11T18:31:16.149946600
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis_udp")

platform = client.get_component(name="platform")
domain = platform.get_domain(name="standalone_ps7_cortexa9_0")

status = domain.set_lib(lib_name="lwip220", path="$COMPONENT_LOCATION/../../../../../Vivado/2025.2.1/data/embeddedsw/ThirdParty/sw_services/lwip220_v1_3")

status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

vitis.dispose()

