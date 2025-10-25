package com.ensolvers.dratauploader;

import jakarta.validation.constraints.NotNull;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@SpringBootApplication
@RestController
@Validated
public class UploadController {

    private final DrataService drata;

    public UploadController(DrataService drata) {
        this.drata = drata;
    }

    public static void main(String[] args) {
        SpringApplication.run(UploadController.class, args);
    }

    /**
     * POST /upload
     * Send exactly four files: file1..file4
     * Env var required: DRATA_API_KEY (Bearer)
     * Static email is in DrataService.EMAIL (change to your target user).
     */
    @PostMapping(
            path = "/upload",
            consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<Map<String, Object>> uploadEvidence(
            @RequestPart("encryptionFile") @NotNull MultipartFile encryptionFile,
            @RequestPart("lockscreenFile") @NotNull MultipartFile lockscreenFile,
            @RequestPart("passwordManagerFile") @NotNull MultipartFile passwordManagerFile,
            @RequestPart("softwareUpdateFile") @NotNull MultipartFile softwareUpdateFile,
            @RequestPart("antivirusFile") @NotNull MultipartFile antivirusFile
    ) throws Exception {
        Map<String, Object> result = drata.uploadEvidence(encryptionFile, lockscreenFile, passwordManagerFile, softwareUpdateFile, antivirusFile);
        return ResponseEntity.ok(result);
    }
}
