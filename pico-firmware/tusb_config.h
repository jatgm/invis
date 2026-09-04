/*
 * tusb_config.h - TinyUSB Configuration for Raspberry Pi Pico Location Spoofer
 */

#ifndef _TUSB_CONFIG_H_
#define _TUSB_CONFIG_H_

#ifdef __cplusplus
 extern "C" {
#endif

// Device mode & Port
#define CFG_TUSB_RHPORT0_MODE       (OPT_MODE_DEVICE | OPT_MODE_FULL_SPEED)
#define CFG_TUSB_OS                 OPT_OS_NONE

#ifndef CFG_TUD_ENDPOINT0_SIZE
#define CFG_TUD_ENDPOINT0_SIZE      64
#endif

// CDC Class Configuration
#define CFG_TUD_CDC                 1
#define CFG_TUD_CDC_RX_BUFSIZE      1024
#define CFG_TUD_CDC_TX_BUFSIZE      1024
#define CFG_TUD_CDC_EP_BUFSIZE      64

// Optional CDC-NCM Ethernet Gadget support for iOS
#ifndef CFG_TUD_NCM
#define CFG_TUD_NCM                 0
#endif

#ifdef __cplusplus
 }
#endif

#endif /* _TUSB_CONFIG_H_ */
