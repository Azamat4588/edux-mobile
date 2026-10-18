# EduX varaqa o'quvchisi (iOS): C++ yadro Classes/ dagi yo'naltiruvchi fayllar orqali ../src dan yig'iladi.
Pod::Spec.new do |s|
  s.name             = 'edux_omr'
  s.version          = '1.0.0'
  s.summary          = "EduX javob varaqasini telefonda o'qish"
  s.description      = 'ArUco belgilar, QR (quirc) va doirachalarni o\'qiydigan C++ yadro, dart:ffi orqali chaqiriladi.'
  s.homepage         = 'https://edux.uz'
  s.license          = { :type => 'Proprietary', :text => 'EduX' }
  s.author           = { 'EduX' => 'info@edux.uz' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.library = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_OPTIMIZATION_LEVEL' => '3',
  }
  s.swift_version = '5.0'
end
