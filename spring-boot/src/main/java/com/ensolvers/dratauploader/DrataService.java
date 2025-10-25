package com.ensolvers.dratauploader;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.*;

@Service
public class DrataService {

    // ←—— Set this to the target user’s email (or make a setter/env mapping)
    public static String EMAIL = "esteban@ensolvers.com";

    private static final String DRATA_HOST = "https://public-api.drata.com";
    private static final String BASE_V2    = DRATA_HOST + "/public/v2";
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Value("${API_KEY}")
    private String apiKey;

    private final RestTemplate rest = new RestTemplate();

    private String apiKey() {
        return apiKey;
    }

    private HttpHeaders authJson() {
        HttpHeaders h = new HttpHeaders();
        h.setBearerAuth(apiKey());
        h.setAccept(List.of(MediaType.APPLICATION_JSON));
        return h;
    }

    public Map<String, Object> uploadEvidence(MultipartFile encryptionFile, MultipartFile lockscreenFile,
                                              MultipartFile passwordManagerFile, MultipartFile softwareUpdateFile, MultipartFile antivirusFile) throws IOException {
        // 1) Resolve Personnel by email: use "email:<email>" path trick
        Long personnelId = getPersonnelIdByEmail(EMAIL);

        // 2) Get first device for that personnel
        Long deviceId = getFirstDeviceIdForPersonnel(personnelId);

        // 3) Upload four evidence docs (map to common device evidence types)
        // Order: PASSWORD_MANAGER, AUTO_UPDATES, HARD_DRIVE_ENCRYPTION, LOCK_SCREEN_EVIDENCE (adjust as you wish)
        String[] types = new String[] {
                "PASSWORD_MANAGER_EVIDENCE",
                "AUTO_UPDATES_EVIDENCE",
                "HARD_DRIVE_ENCRYPTION_EVIDENCE",
                "LOCK_SCREEN_EVIDENCE",
                "ANTIVIRUS_EVIDENCE"
        };
        MultipartFile[] files = new MultipartFile[] { passwordManagerFile, softwareUpdateFile, encryptionFile, lockscreenFile, antivirusFile };

        List<Map<String, Object>> uploads = new ArrayList<>();
        for (int i = 0; i < files.length; i++) {
            this.deleteDeviceDocumentsByType(deviceId, types[i]);
            uploads.add(uploadDeviceDocument(deviceId, types[i], files[i]));
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("personnelEmail", EMAIL);
        out.put("personnelId", personnelId);
        out.put("deviceId", deviceId);
        out.put("uploads", uploads);
        return out;
    }

    /**
     * Deletes all device documents of a specific Drata evidence type for a device.
     *
     * @param deviceId the device to clean
     * @param documentType the Drata document evidence type, e.g.
     *                     "PASSWORD_MANAGER_EVIDENCE",
     *                     "AUTO_UPDATES_EVIDENCE",
     *                     "HARD_DRIVE_ENCRYPTION_EVIDENCE",
     *                     "ANTIVIRUS_EVIDENCE",
     *                     "LOCK_SCREEN_EVIDENCE"
     * @return a list summarizing deleted documentIds and statuses
     * @throws IOException for JSON parsing issues
     */
    private List<Map<String, Object>> deleteDeviceDocumentsByType(long deviceId, String documentType) throws IOException {
        // 1) List existing documents
        String listUrl = BASE_V2 + "/devices/" + deviceId + "/documents?size=1000";
        HttpEntity<Void> listReq = new HttpEntity<>(authJson());
        ResponseEntity<String> listResp = rest.exchange(listUrl, HttpMethod.GET, listReq, String.class);
        JsonNode root = MAPPER.readTree(listResp.getBody());
        JsonNode dataArr = root.path("documents");

        if (!dataArr.isArray()) {
            throw new IllegalStateException("Unexpected response format listing device documents.");
        }

        List<Map<String, Object>> results = new ArrayList<>();

        // 2) Loop and delete only matching types
        for (JsonNode docNode : dataArr) {
            String type = docNode.path("type").asText();
            long docId = docNode.path("id").asLong(-1);

            if (!documentType.equals(type) || docId < 0) {
                continue; // skip non-matching types
            }

            String deleteUrl = BASE_V2 + "/devices/" + deviceId + "/documents/" + docId;
            HttpEntity<Void> delReq = new HttpEntity<>(authJson());

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("documentId", docId);
            result.put("type", type);

            try {
                ResponseEntity<String> delResp = rest.exchange(deleteUrl, HttpMethod.DELETE, delReq, String.class);
                if (delResp.getStatusCode().is2xxSuccessful()) {
                    result.put("status", "deleted");
                } else {
                    result.put("status", "error");
                    result.put("httpStatus", delResp.getStatusCodeValue());
                    result.put("body", delResp.getBody());
                }
            } catch (HttpClientErrorException e) {
                result.put("status", "error");
                result.put("httpStatus", e.getRawStatusCode());
                result.put("error", e.getResponseBodyAsString());
            }

            results.add(result);
        }

        return results;
    }

    private Long getPersonnelIdByEmail(String email) {
        // V2 supports "email:<address>" as the {personnelId} param for fetch-by-email
        // GET /public/v2/personnel/{personnelId}?expand[]=user
        String url = BASE_V2 + "/personnel/" + "email:" + email + "?expand[]=user";

        HttpEntity<Void> req = new HttpEntity<>(authJson());
        ResponseEntity<String> resp = rest.exchange(url, HttpMethod.GET, req, String.class);
        try {
            JsonNode root = MAPPER.readTree(resp.getBody());
            JsonNode idNode = root.get("id");
            if (idNode == null || !idNode.isNumber()) {
                throw new IllegalStateException("Personnel not found for email: " + email);
            }
            return Long.valueOf(idNode.longValue());
        } catch (IOException e) {
            throw new RuntimeException("Failed parsing personnel response", e);
        } catch (HttpClientErrorException.NotFound nf) {
            throw new IllegalStateException("Personnel not found for email: " + email);
        }
    }

    private Long getFirstDeviceIdForPersonnel(long personnelId) {
        // GET /public/v2/personnel/{personnelId}/devices?size=1
        String url = BASE_V2 + "/personnel/" + personnelId + "/devices?size=1";

        HttpEntity<Void> req = new HttpEntity<>(authJson());
        ResponseEntity<String> resp = rest.exchange(url, HttpMethod.GET, req, String.class);
        try {
            JsonNode root = MAPPER.readTree(resp.getBody());
            JsonNode data = root.get("data");
            if (data == null || !data.isArray() || data.size() == 0) {
                throw new IllegalStateException("No devices for personnelId=" + personnelId);
            }
            JsonNode first = data.get(0);
            return Long.valueOf(first.get("id").asLong());
        } catch (IOException e) {
            throw new RuntimeException("Failed parsing devices response", e);
        }
    }

    private Map<String, Object> uploadDeviceDocument(long deviceId, String type, MultipartFile file) throws IOException {
        // POST /public/v2/devices/{deviceId}/documents
        String url = BASE_V2 + "/devices/" + deviceId + "/documents";

        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(apiKey());
        headers.setContentType(MediaType.MULTIPART_FORM_DATA);

        // Wrap the file so RestTemplate sets a filename
        ByteArrayResource resource = new ByteArrayResource(file.getBytes()) {
            @Override public String getFilename() {
                return Optional.ofNullable(file.getOriginalFilename()).orElse("evidence.bin");
            }
        };

        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        body.add("type", type);
        body.add("file", resource);

        HttpEntity<MultiValueMap<String, Object>> req = new HttpEntity<>(body, headers);
        ResponseEntity<String> resp = rest.exchange(url, HttpMethod.POST, req, String.class);

        // Return minimal info from Drata’s response
        JsonNode root = MAPPER.readTree(resp.getBody());
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("type", type);
        info.put("documentId", Long.valueOf(root.path("id").asLong()));
        info.put("name", root.path("name").asText(null));
        info.put("createdAt", root.path("createdAt").asText(null));
        return info;
    }
}
