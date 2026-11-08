# 기능 분류: Finder 설치 창. 앱과 Applications만 보이고 배경/보조 파일은 숨긴다.
from pathlib import Path
import unicodedata
root = Path(defines.get('root', Path.cwd())).resolve()
application = str(Path(defines.get('app', root / 'dist/ZCRE 서포터.app')).resolve())
files = [application]
symlinks = {'Applications': '/Applications'}
format = 'UDZO'
filesystem = 'HFS+'
background = str(root / 'Resources/Installer/background.tiff')
icon = str(Path(application) / 'Contents/Resources/AppIcon.icns')
# HFS+는 한글 파일명을 NFD로 저장하므로 Finder 좌표 키도 동일하게 정규화한다.
icon_locations = {unicodedata.normalize('NFD', 'ZCRE 서포터.app'): (204, 215), 'Applications': (516, 215)}
window_rect = ((180, 180), (720, 492))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
show_icon_preview = False
arrange_by = None
grid_offset = (0, 0)
icon_size = 96
text_size = 12
label_pos = 'bottom'
scroll_position = (0, 0)
