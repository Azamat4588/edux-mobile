// EduX javob varaqasini telefonning o'zida o'qish (C interfeys).
//
// Serverdagi OMR servis (omr-service/omr/scanner.py) bilan bir xil varaqa o'lchamlari va bir xil
// o'qish qoidalari: burchakdagi 4 ta ArUco belgi (DICT_4X4_50, id 0..3) -> varaqani to'g'rilash -> QR ->
// yorug'likni tekislash -> doirachalar. Natija JSON satr sifatida qaytadi; xotira omr_free() bilan bo'shatiladi.
#ifndef EDUX_OMR_H
#define EDUX_OMR_H

#include <stdint.h>

#if defined(_WIN32)
#define OMR_EXPORT __declspec(dllexport)
#else
#define OMR_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Kamera kadrida varaqani qidiradi (jonli ko'rsatma uchun, tez).
// gray — kulrang kadr (kameraning Y tekisligi), stride — qator uzunligi baytda.
// work_max_side — tahlil o'lchami (masalan 800): kadr shu o'lchamgacha kichraytiriladi.
// Javob: {"found":n,"markers":[{"id":0,"x":..,"y":..}],"quad":[[x,y]x4]|null,"px_per_mm":..,
//         "sharpness":0..1,"brightness":0..255,"ms":..}  (koordinatalar kirish kadrida)
OMR_EXPORT char* omr_detect(const uint8_t* gray, int width, int height, int stride, int work_max_side);

// Kadrni to'liq o'qiydi. questions/options — QR o'qilmasa ishlatiladigan shakl (0 — noma'lum).
// preview_jpeg — to'g'rilangan varaqa (3 px/mm), upload_jpeg — serverga yuboriladigan kadr (uzun tomoni <= 2000).
// Ikkalasi ham NULL bo'lishi mumkin (kerak bo'lmasa). Ajratilgan xotira omr_free() bilan bo'shatiladi.
OMR_EXPORT char* omr_read_gray(const uint8_t* gray, int width, int height, int stride, int questions, int options,
                               uint8_t** preview_jpeg, int* preview_len, uint8_t** upload_jpeg, int* upload_len);

// JPEG/PNG fayldan (galereya) o'qiydi. Qolgani omr_read_gray bilan bir xil.
OMR_EXPORT char* omr_read_encoded(const uint8_t* data, int length, int questions, int options,
                                  uint8_t** preview_jpeg, int* preview_len, uint8_t** upload_jpeg, int* upload_len);

// Kadrni JPEG ga o'giradi (serverga yuborish uchun). max_side — uzun tomon chegarasi (0 — o'zgarmaydi).
// Qaytaradi: JPEG hajmi (0 — xato). Xotira omr_free() bilan bo'shatiladi.
OMR_EXPORT int omr_encode_jpeg(const uint8_t* gray, int width, int height, int stride, int max_side, int quality,
                               uint8_t** jpeg, int* jpeg_len);

OMR_EXPORT void omr_free(void* pointer);

// Varaqa shakli versiyasi (layout.py dagi LAYOUT_VERSION bilan bir xil).
OMR_EXPORT int omr_layout_version(void);

#ifdef __cplusplus
}
#endif

#endif
