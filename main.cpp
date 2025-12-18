#include <opencv2/opencv.hpp>
#include <opencv2/dnn.hpp>
#include <iostream>
#include <fstream>
#include <vector>
#include <map>
#include <algorithm>
#include <ctime>
#include <iomanip>
#include "json.hpp" 

using namespace cv;
using namespace cv::dnn;
using namespace std;
using json = nlohmann::json;

// === CONFIGURATION ===
const string VIDEO_FILE = "test.mp4"; // Set to "" for Webcam input
const int PROC_W = 854; // 480p resolution (Optimized for inference speed)
const int PROC_H = 480;

// TRACKING PARAMETERS
const double MAX_TRACK_DIST = 100.0; // Max pixels to match existing object

// UI COLORS
const Scalar COLOR_BG(30, 30, 30);
const Scalar COLOR_TEXT(255, 255, 255);
const Scalar COLOR_ACCENT(0, 255, 200);

// === DATA STRUCTURES ===

// Stores the result of a single classification model
struct ClassResult {
    int id;
    string label;
    float confidence;
    Mat inputImage; // Stored for visualization/debugging
};

// Represents a bounding box detected by YOLO
struct Detection {
    int classId;
    float confidence;
    Rect box;
    Point center() { return Point(box.x + box.width / 2, box.y + box.height / 2); }
};

// Represents a persistent object being tracked across frames
struct TrackedObject {
    int id;
    Rect box;
    string label;
    float confidence;
    int lostFrames; // Counter for object persistence logic
    vector<pair<string, ClassResult>> debugData; // Stores votes from ensemble
    Point center() { return Point(box.x + box.width / 2, box.y + box.height / 2); }
};

// === UTILITIES ===

class Logger {
    ofstream logFile;
    bool enabled = false;
public:
    Logger(string filename) { logFile.open(filename, ios::app); }
    void toggle() { enabled = !enabled; }
    bool isEnabled() { return enabled; }
    
    void log(string mode, string label, float conf) {
        if (!enabled) return;
        // Get current time safely
        auto t = time(nullptr); 
        struct tm tm; 
        #ifdef _WIN32
            localtime_s(&tm, &t); // Windows-specific safe version
        #else
            localtime_r(&t, &tm); // Linux/Mac version
        #endif
        
        logFile << put_time(&tm, "[%H:%M:%S]") << " | " << mode 
                << " -> " << label << " (" << (int)(conf * 100) << "%)" << endl;
    }
};

// === 1. REGION PROPOSAL (Computer Vision Heuristics) ===
// Fast algorithm to find "Regions of Interest" (ROI) based on contrast/motion.
// This reduces the load on the heavy Neural Networks.
vector<Rect> proposeRegions(Mat& frame) {
    Mat gray, blur, thresh;
    cvtColor(frame, gray, COLOR_BGR2GRAY);
    GaussianBlur(gray, blur, Size(5, 5), 0);

    // Adaptive Threshold handles varying lighting conditions better than fixed thresh.
    // Block size (15) and C (3) might need tuning for different environments.
    adaptiveThreshold(blur, thresh, 255, ADAPTIVE_THRESH_GAUSSIAN_C, THRESH_BINARY_INV, 15, 3);

    // Morphological operations to remove noise (speckles)
    Mat kernel = getStructuringElement(MORPH_RECT, Size(5, 5));
    morphologyEx(thresh, thresh, MORPH_CLOSE, kernel); // Connect gaps
    morphologyEx(thresh, thresh, MORPH_OPEN, kernel);  // Remove small noise

    vector<vector<Point>> contours;
    findContours(thresh, contours, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);

    vector<Rect> regions;
    for (const auto& cnt : contours) {
        double area = contourArea(cnt);
        // Filter out very small noise and very large shadows/artifacts
        if (area > 3000 && area < (frame.cols * frame.rows * 0.7)) {
            regions.push_back(boundingRect(cnt));
        }
    }
    return regions;
}

// Simple color/statistical analysis for "Math" voting layer
pair<int, string> quickMathClassify(Mat& roi) {
    if (roi.empty()) return { -1, "Unknown" };
    Mat hsv; cvtColor(roi, hsv, COLOR_BGR2HSV);
    Scalar mean, std; meanStdDev(hsv, mean, std);
    
    double S = mean[1]; 
    double V = mean[2];

    // Heuristic rules based on material properties
    if (S < 40 && V > 160) return { 2, "Paper (Math)" };
    if (std[2] > 55) return { 1, "Glass (Math)" };
    return { 0, "Plastic (Math)" };
}

// === 2. OBJECT DETECTION (YOLO) ===
class YoloDetector {
    Net net;
    const float INPUT_W = 640.0; 
    const float INPUT_H = 640.0;
public:
    YoloDetector(string path) {
        try { 
            net = readNetFromONNX(path); 
            net.setPreferableBackend(DNN_BACKEND_OPENCV); 
            net.setPreferableTarget(DNN_TARGET_CPU); 
        } catch (...) { cerr << "Error loading YOLO model!" << endl; }
    }

    vector<Detection> detect(Mat& img) {
        if (net.empty() || img.empty()) return {};
        
        // Preprocess: Blob from image (resizing + normalization)
        Mat blob; 
        blobFromImage(img, blob, 1.0 / 255.0, Size(INPUT_W, INPUT_H), Scalar(), true, false);
        net.setInput(blob);
        
        // Forward pass
        Mat out = net.forward();
        
        // YOLOv8/v11 Output parsing (Transposing output matrix)
        Mat out_t = out.reshape(1, out.size[1]).t();
        float* data = (float*)out_t.data;
        
        vector<Rect> boxes; 
        vector<float> confs; 
        vector<int> ids;

        for (int i = 0; i < out_t.rows; ++i) {
            float* row = data + (i * out_t.cols);
            Mat s(1, out_t.cols - 4, CV_32F, row + 4); // Class scores
            Point p; double score; minMaxLoc(s, 0, &score, 0, &p);

            if (score > 0.4) {
                float cx = row[0], cy = row[1], w = row[2], h = row[3];
                // Map coordinates back to original image size
                int l = int((cx - 0.5 * w) * (img.cols / INPUT_W));
                int t = int((cy - 0.5 * h) * (img.rows / INPUT_H));
                
                boxes.push_back(Rect(l, t, int(w * (img.cols / INPUT_W)), int(h * (img.rows / INPUT_H))));
                confs.push_back((float)score); 
                ids.push_back(p.x);
            }
        }
        
        // Non-Maximum Suppression (NMS) to remove overlapping boxes
        vector<int> idx; 
        NMSBoxes(boxes, confs, 0.4, 0.4, idx);
        
        vector<Detection> res; 
        for (int i : idx) res.push_back({ ids[i], confs[i], boxes[i] });
        return res;
    }
};

// === 3. CLASSIFICATION ENSEMBLE ===
// Wrapper for ResNet, MobileNet, and ViT models
class Classifier {
    Net net; 
    Size sz; 
    string name; 
    vector<string> labels;
public:
    Classifier(string folder, string n) : name(n) {
        sz = Size(224, 224); // Standard input size for classification models
        try { 
            net = readNetFromONNX(folder + "/model.onnx"); 
            net.setPreferableBackend(DNN_BACKEND_OPENCV); 
            net.setPreferableTarget(DNN_TARGET_CPU); 
        } catch (...) { cerr << "Failed to load model: " << name << endl; }

        // Load labels from JSON config
        ifstream f(folder + "/config.json");
        if (f.is_open()) {
            try { 
                json j = json::parse(f); 
                for (auto& el : j["id2label"].items()) { 
                    int id = stoi(el.key());
                    if (id >= labels.size()) labels.resize(id + 1); 
                    labels[id] = el.value(); 
                } 
            } catch (...) {}
        }
        if (labels.empty()) labels = { "Plastic", "Glass", "Paper" }; // Fallback defaults
    }

    ClassResult predict(Mat& img) {
        if (img.empty() || net.empty()) return { -1, "Err", 0, Mat() };
        
        Mat blob, vis; 
        resize(img, vis, sz); 
        cvtColor(vis, vis, COLOR_BGR2RGB);

        // ImageNet Normalization
        vis.convertTo(blob, CV_32F, 1.0 / 255.0);
        subtract(blob, Scalar(0.485, 0.456, 0.406), blob); 
        divide(blob, Scalar(0.229, 0.224, 0.225), blob);
        
        blobFromImage(blob, blob, 1.0, sz, Scalar(), false, false);
        net.setInput(blob);
        
        Mat out = net.forward();
        
        // Softmax
        double maxL; minMaxLoc(out, 0, &maxL); 
        out -= maxL; exp(out, out); out /= sum(out)[0];

        Point p; double conf; 
        minMaxLoc(out, 0, &conf, 0, &p);
        
        int id = p.x % labels.size(); // Safety modulo
        Mat disp; cvtColor(vis, disp, COLOR_RGB2BGR);
        
        return { id, labels[id], (float)conf, disp };
    }

    string getName() { return name; }
    string getLabel(int id) { return (id < labels.size()) ? labels[id] : "Unknown"; }
};

// Helper: Add padding to a bounding box
Rect expand(Rect b, int w, int h, float p) {
    int wp = b.width * p; 
    int hp = b.height * p;
    return Rect(max(0, b.x - wp), max(0, b.y - hp), 
                min(w - b.x, b.width + 2 * wp), min(h - b.y, b.height + 2 * hp)) & Rect(0, 0, w, h);
}

// === DASHBOARD VISUALIZATION ===
void drawDash(Mat& can, TrackedObject* obj) {
    int y = 20;
    putText(can, "CASCADE MODE (OPTIMIZED)", Point(20, y += 20), 2, 0.6, COLOR_ACCENT, 1);
    line(can, Point(20, y += 10), Point(330, y), Scalar(100, 100, 100), 1);

    if (obj == nullptr) {
        putText(can, "WAITING FOR OBJECT...", Point(60, can.rows / 2), 1, 0.8, Scalar(100, 100, 100), 1);
        return;
    }

    putText(can, "TRACK ID: " + to_string(obj->id), Point(20, y += 30), 1, 0.8, COLOR_TEXT, 1);
    putText(can, "CONSENSUS:", Point(20, y += 30), 1, 1.0, COLOR_TEXT, 1);
    putText(can, obj->label, Point(20, y += 30), 1, 2.0, Scalar(0, 255, 0), 2);

    y += 20;
    // Draw individual votes from the ensemble
    for (auto& r : obj->debugData) {
        if (!r.second.inputImage.empty()) {
            Mat ico; resize(r.second.inputImage, ico, Size(60, 60));
            ico.copyTo(can(Rect(20, y += 10, 60, 60)));
            putText(can, r.first, Point(90, y + 20), 1, 0.8, COLOR_ACCENT);
            putText(can, r.second.label + " " + to_string((int)(r.second.confidence * 100)) + "%", 
                    Point(90, y + 45), 0, 0.5, COLOR_TEXT);
            y += 60;
        } else {
            putText(can, r.first, Point(20, y += 25), 1, 0.8, COLOR_ACCENT);
            putText(can, r.second.label, Point(20, y += 20), 0, 0.5, Scalar(150, 150, 150));
        }
    }
}

// === MAIN LOOP ===
int main() {
    Logger logger("log.txt");
    
    // Initialize Models
    YoloDetector yolo("models/yolo/model.onnx");
    vector<Classifier*> ens;
    ens.push_back(new Classifier("models/resnet", "ResNet"));
    ens.push_back(new Classifier("models/mobilenet", "Mobile"));
    ens.push_back(new Classifier("models/vit", "ViT (Transformer)")); // Vision Transformer

    VideoCapture cap;
    if (VIDEO_FILE.empty()) cap.open(0);
    else { 
        cap.open(VIDEO_FILE); 
        if (!cap.isOpened()) cap.open(VIDEO_FILE, CAP_ANY); 
    }
    if (!cap.isOpened()) { cerr << "Cannot open video source!" << endl; return -1; }

    Mat frame;
    TickMeter tm;

    vector<TrackedObject> trackers;
    int nextId = 1;
    bool useCascade = true;

    while (true) {
        tm.start();
        cap >> frame;
        if (frame.empty()) {
            if (!VIDEO_FILE.empty()) { cap.set(CAP_PROP_POS_FRAMES, 0); continue; } // Loop video
            break;
        }
        resize(frame, frame, Size(PROC_W, PROC_H));

        int key = waitKey(1);
        if (key == 27) break; // ESC
        if (key == 9) useCascade = !useCascade; // TAB toggles mode
        if (key == 'l' || key == 'L') logger.toggle();

        // STEP 1: REGION PROPOSAL (Always active, lightweight)
        vector<Rect> regions = proposeRegions(frame);

        // Increment lost counters
        for (auto& t : trackers) t.lostFrames++;

        if (useCascade) {
            // === CASCADE MODE (SMART & FAST) ===
            for (auto& rawRect : regions) {

                // A) TRACKING CHECK: Is this a known object?
                Point center = (rawRect.tl() + rawRect.br()) * 0.5;
                int matchIdx = -1;
                double minD = MAX_TRACK_DIST;

                for (int i = 0; i < trackers.size(); ++i) {
                    double d = norm(trackers[i].center() - center);
                    if (d < minD) { minD = d; matchIdx = i; }
                }

                if (matchIdx != -1) {
                    // MATCH FOUND -> Update coordinates, skip heavy inference
                    trackers[matchIdx].box = rawRect;
                    trackers[matchIdx].lostFrames = 0;
                }
                else {
                    // B) NEW OBJECT CANDIDATE -> Run Deep Learning Verification
                    // Add padding for better context
                    Rect yoloRect = expand(rawRect, frame.cols, frame.rows, 0.2); 
                    Mat crop = frame(yoloRect);

                    // Run Object Detection
                    vector<Detection> yd = yolo.detect(crop);

                    if (!yd.empty()) {
                        // C) DETECTION CONFIRMED -> Run Ensemble Classification
                        Detection det = yd[0]; 

                        // Remap coords back to full frame
                        det.box.x += yoloRect.x;
                        det.box.y += yoloRect.y;

                        // Create new tracker
                        TrackedObject obj;
                        obj.id = nextId++;
                        obj.box = det.box;
                        obj.lostFrames = 0;

                        // Run Classifiers (ResNet, ViT, MobileNet)
                        Rect clsRect = expand(det.box, frame.cols, frame.rows, 0.05);
                        Mat clsCrop = frame(clsRect);

                        map<int, float> votes;
                        votes[det.classId] += 2.0; // Base vote from YOLO

                        for (auto* c : ens) {
                            ClassResult r = c->predict(clsCrop);
                            // Weight ViT higher due to attention mechanism accuracy
                            float w = (c->getName().find("ViT") != string::npos) ? 1.3 : 1.0;
                            votes[r.id] += w;
                            obj.debugData.push_back({ c->getName(), r });
                        }

                        // Add Math heuristics vote
                        pair<int, string> mr = quickMathClassify(clsCrop);
                        votes[mr.first] += 0.8;
                        obj.debugData.push_back({ "Math Heuristics", {mr.first, mr.second, 1.0, Mat()} });

                        // Consensus Voting
                        int win = -1; float maxS = -1;
                        for (auto& [id, s] : votes) if (s > maxS) { maxS = s; win = id; }

                        obj.label = (win != -1) ? ens[0]->getLabel(win) : "Unknown";
                        trackers.push_back(obj);
                        logger.log("NEW_TRACK", obj.label, 1.0);
                    }
                    // If YOLO returns nothing, ignore the region (it was noise/shadow)
                }
            }
        }
        else {
            // === DEBUG MODE (REGION PROPOSAL ONLY) ===
            trackers.clear(); 
            for (auto& r : regions) {
                TrackedObject obj;
                obj.box = r;
                obj.label = "Region";
                obj.id = 0;
                trackers.push_back(obj);
            }
        }

        // Cleanup lost trackers
        trackers.erase(remove_if(trackers.begin(), trackers.end(), 
            [](const TrackedObject& t) {return t.lostFrames > 10; }), trackers.end());

        // Draw UI
        Mat dash(frame.rows, 350, CV_8UC3, COLOR_BG);
        TrackedObject* main = nullptr;
        for (auto& t : trackers) {
            Scalar clr = useCascade ? Scalar(0, 255, 0) : Scalar(0, 165, 255);
            rectangle(frame, t.box, clr, 2);
            putText(frame, t.label + (useCascade ? " ID:" + to_string(t.id) : ""), 
                    Point(t.box.x, t.box.y - 10), 1, 1.5, clr, 2);
            if (main == nullptr || t.box.area() > main->box.area()) main = &t;
        }

        string modeText = useCascade ? "[TAB] MODE: CASCADE (AI)" : "[TAB] MODE: REGION PROPOSAL (RAW)";
        putText(frame, modeText, Point(10, 30), 1, 1.5, useCascade ? Scalar(0, 255, 0) : Scalar(0, 0, 255), 2);

        if (useCascade) drawDash(dash, main);

        tm.stop();
        putText(frame, "FPS: " + to_string((int)tm.getFPS()), Point(10, 70), 1, 2.0, Scalar(0, 255, 255), 2);
        tm.reset();

        Mat combo; 
        hconcat(frame, dash, combo);
        imshow("AI Sorter Dashboard", combo);
    }
    
    for (auto c : ens) delete c;
    return 0;
}
