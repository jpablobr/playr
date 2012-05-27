# $LOAD_PATH.unshift '/playr/'
require 'playr'
Playr::Conf.music_dir = '~/music/'
Playr::Conf.mpd_dir = '~/.private/.mpd/'
Playr::Conf.playlists_dir = Playr::Conf.mpd_dir + "playlists/"
Playr::Conf.playlists = {
  fav: Playr::Conf.playlists_dir + 'fav.m3u'
}
