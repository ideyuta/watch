'use strict'
browserSync = require 'browser-sync'
browserify = require 'browserify'
del = require 'del'
eslintFriendlyFormatter = require 'eslint-friendly-formatter'
isparta = require 'isparta'
path = require 'path'
replaceExt = require 'replace-ext'
runSequence = require 'run-sequence'
source = require 'vinyl-source-stream'
through = require 'through2'
vinylPaths = require 'vinyl-paths'
watchify = require 'watchify'

gulp = require 'gulp'
$ =
  eslint: require 'gulp-eslint'
  imagemin: require 'gulp-imagemin'
  istanbul: require 'gulp-istanbul'
  jade: require 'gulp-jade'
  mocha: require 'gulp-mocha'
  notify: require 'gulp-notify'
  packager: require 'electron-packager'
  plumber: require 'gulp-plumber'
  rename: require 'gulp-rename'
  sourcemaps: require 'gulp-sourcemaps'
  stylus: require 'gulp-stylus'
  util: require 'gulp-util'
  watch: require 'gulp-watch'

DIRS_DIST = 'dist'
DIRS_SRC = 'src'
DIRS_TEST = 'test'
DIRS_PREVIEW = 'preview'
DIRS_RELEASE = 'release'
DIRS_COVERAGE = 'coverage'
PATHS_BROWSERIFY = ["#{DIRS_SRC}/app.js"]
PATHS_JADE = ["#{DIRS_SRC}/**/*.jade", "!#{DIRS_SRC}/**/__preview__/*.jade"]
PATHS_JS = ["#{DIRS_SRC}/**/*.js"]
PATHS_STYLUS = "#{DIRS_SRC}/styles/*.styl"
PATHS_WATCH_STYLUS = "#{DIRS_SRC}/styles/**/*.styl"
PATHS_IMAGE = "#{DIRS_SRC}/images/**/*.{png,jpg,gif}"
PATHS_TEST = ["#{DIRS_TEST}/**/*.js"]
PATHS_ESLINT = [].concat(PATHS_JS, PATHS_TEST)
PATHS_PREVIEW_JADE = "#{DIRS_PREVIEW}/**/index.jade"
PATHS_PREVIEW_BROWSERIFY = "#{DIRS_PREVIEW}/**/index.js"
PATHS_PACKAGE_IGNORES = [
  DIRS_SRC,
  DIRS_TEST,
  DIRS_PREVIEW,
  DIRS_COVERAGE,
  DIRS_RELEASE
]
THROUGH_ERROR = process.env.THROUGH_ERROR is '1'


###
# JS
###

# Browserify
gulp.task 'browserify', ->
  PATHS_BROWSERIFY.forEach (fp) ->
    buildName = path.basename(fp)
    bundler = browserify
      cache: {}
      entries: fp
      packageCache: {}
    .transform 'babelify'

    bundle = ->
      $.util.log 'Starting browserify', $.util.colors.cyan(buildName)
      bundler.bundle()
        .on 'error', errorHandler
        .pipe source buildName
        .pipe gulp.dest DIRS_DIST
        .on 'end', ->
          $.util.log 'Finished browserify', $.util.colors.cyan(buildName)
          browserSync.reload once: true
    bundler = watchify bundler
    bundler.on 'update', bundle
    bundle()

# Mocha
gulp.task 'mocha', (cb) ->
  # 詳細オプションがない場合は簡易表示
  require('espower-babel/guess')
  opts =
    mocha: reporter: 'nyan'
    istanbul: reporters: ['lcov', 'json', 'html', 'text-summary']
  gulp.src PATHS_JS
    .pipe handleError()
    .pipe $.istanbul
      instrumenter: isparta.Instrumenter
      # mocha の実行前にこの設定が登録されるので
      # espower-babel 用のオプション設定は不要
      babel:
        stage: 0,
        optional: ['runtime']
        plugins: ['babel-plugin-rewire']
    .pipe $.istanbul.hookRequire()
    .on 'finish', ->
      gulp.src PATHS_TEST
        .pipe handleError()
        .pipe $.mocha opts.mocha
        .pipe $.istanbul.writeReports opts.istanbul
        .on 'end', cb
  return false

# ESLint
gulp.task 'eslint', ->
  errorFunc = if THROUGH_ERROR then 'failAfterError' else 'failOnError'
  gulp.src PATHS_ESLINT
    .pipe handleError()
    .pipe $.eslint useEslintrc: true
    .pipe $.eslint[errorFunc]()
    .pipe $.eslint.format(eslintFriendlyFormatter)


###
# CSS
###

# stylus コンパイル
gulp.task 'stylus', ->
  gulp.src PATHS_STYLUS
    .pipe handleError()
    .pipe $.sourcemaps.init()
    .pipe $.stylus
      'include css': true
    .pipe $.sourcemaps.write()
    .pipe gulp.dest "#{DIRS_DIST}/styles"
    .pipe browserSync.reload stream: true, once: true


###
# Image
###

# 画像の最適化
gulp.task 'image', ->
  gulp.src PATHS_IMAGE
    .pipe handleError()
    .pipe $.imagemin
      progressive: true
      interlaced: true
    .pipe gulp.dest "#{DIRS_DIST}/images/"


###
# JADE
###

gulp.task 'jade', ->
  gulp.src PATHS_JADE
    .pipe handleError()
    .pipe $.jade pretty: true
    .pipe gulp.dest DIRS_DIST
    .pipe browserSync.reload stream: true, once: true


###
# プレビュー
###

# Browserify
gulp.task 'preview:browserify', ->
  gulp.src PATHS_PREVIEW_BROWSERIFY
    .pipe handleError()
    .pipe vinylPaths (fp, cb) ->
      bundler = browserify
        cache: {}
        entries: fp
        packageCache: {}
      .transform 'babelify'
      # 書き出しディレクトリから __preview__ を削除
      # Component>/ 直下に js を配置する
      fp = path.relative "#{DIRS_PREVIEW}", fp
      bundle = ->
        $.util.log 'Starting browserify for preview', $.util.colors.cyan(fp)
        bundler.bundle()
          .on 'error', errorHandler
          .pipe source replaceExt fp, '.js'
          .pipe gulp.dest "#{DIRS_DIST}/preview"
          .on 'end', ->
            $.util.log 'Finished browserify for preview', $.util.colors.cyan(fp)
            browserSync.reload once: true
      bundler = watchify bundler
      bundler.on 'update', bundle
      bundle()
      cb()

gulp.task 'preview:jade', ->
  gulp.src PATHS_PREVIEW_JADE
    .pipe handleError()
    .pipe $.jade pretty: true
    #.pipe $.rename (p) ->
    #  # 書き出しディレクトリから __preview__ を削除
    #  # Component>/ 直下に html を配置する
    #  # p.dirname = path.join p.dirname, '..'
    #  # p
    .pipe gulp.dest "#{DIRS_DIST}/preview"
    .pipe browserSync.reload stream: true, once: true


###
# Package
###

gulp.task 'package', (cb) ->
  $.packager
    dir: './'
    name: 'watch'
    arch: 'x64'
    ignore: PATHS_PACKAGE_IGNORES
    overwrite: true
    platform: 'darwin'
    out: DIRS_RELEASE
    version: '0.30.2'
  , (err) ->
    cb()

###
# 各種ユーティリティ
###

# browser-sync の起動
gulp.task 'browserSync', ->
  browserSync
    logLevel: 'debug'
    reloadDelay: 2
    minify: false
    open: false
    server:
      baseDir: DIRS_DIST

# dist / coverage ディレクトリの削除
gulp.task 'clean:js', del.bind null, [DIRS_DIST]
gulp.task 'clean:cov', del.bind null, [DIRS_COVERAGE]
gulp.task 'clean', ['clean:js', 'clean:cov']

# 各種ファイルの監視・ビルド
gulp.task 'watch', ['jade', 'preview:jade', 'stylus', 'image'], (cb) ->
  $.watch PATHS_JADE, -> gulp.start 'jade'
  $.watch PATHS_PREVIEW_JADE, -> gulp.start 'preview:jade'
  $.watch PATHS_WATCH_STYLUS, -> gulp.start 'stylus'
  $.watch PATHS_TEST, -> gulp.start 'mocha', 'eslint'
  $.watch PATHS_JS, -> gulp.start 'mocha', 'eslint'
  $.watch PATHS_IMAGE, -> gulp.start 'image'
  cb()

# エラー処理
handleError = ->
  if THROUGH_ERROR
    handler = false
  else
    handler = errorHandler
  $.plumber errorHandler: handler

errorHandler = (error) ->
  if not THROUGH_ERROR
    $.notify.onError('<%= error.message %>')(error)


###
# タスク
###

gulp.task 'default', (cb) ->
  runSequence ['clean', 'browserSync'], 'watch', ['browserify', 'preview:browserify'], cb

gulp.task 'build', (cb) ->
  runSequence 'clean:js', ['browserify', 'stylus', 'image', 'jade'], 'package', cb

gulp.task 'test', (cb) ->
  runSequence 'clean', ['eslint', 'mocha']
