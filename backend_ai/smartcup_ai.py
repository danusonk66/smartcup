import json
import os
import sys
import firebase_admin
from firebase_admin import credentials, db
from google import genai
from google.genai import types

# ตั้งค่า Gemini API (อ่านจาก environment variable ห้ามเขียนคีย์ลงในไฟล์นี้)
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    sys.exit("ไม่พบ GEMINI_API_KEY — ตั้งค่าก่อนรัน เช่น  $env:GEMINI_API_KEY=\"คีย์ของคุณ\"")
client = genai.Client(api_key=GEMINI_API_KEY)

# URL Firebase
FIREBASE_DB_URL = "https://testurlesp32-default-rtdb.asia-southeast1.firebasedatabase.app/"

# ไฟล์ service account ต้องไม่ถูกอัปโหลดขึ้น GitHub (ใส่ไว้ใน .gitignore)
SERVICE_ACCOUNT_PATH = os.environ.get("SERVICE_ACCOUNT_PATH", "serviceAccountKey.json")
cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
firebase_admin.initialize_app(cred, {
    'databaseURL': FIREBASE_DB_URL
})

def run_ai_analysis():
    print("⏳ กำลังอ่านข้อมูลจาก Firebase...")
    cup_ref = db.reference('SmartCup')
    cup_data = cup_ref.get() or {}

    today_total = cup_data.get('today_total', 0)
    current_drink = cup_data.get('current_drink_type', 'น้ำเปล่า')
    last_drink_time = cup_data.get('last_drink_time', '12:00')
    streak_days = cup_data.get('streak_days', 0)

    user_context = f"""
    ข้อมูลการดื่มน้ำของผู้ใช้:
    - ปริมาณน้ำที่ดื่มวันนี้: {today_total} ml (เป้าหมาย 2000 ml)
    - ประเภทเครื่องดื่มล่าสุด: {current_drink}
    - เวลาที่ดื่มล่าสุด: {last_drink_time}
    - ดื่มต่อเนื่อง (Streak): {streak_days} วัน
    """

    print("🤖 กำลังส่งให้ Gemini วิเคราะห์...")
    prompt = f"""
    คุณเป็น AI ผู้เชี่ยวชาญด้านสุขภาพและการดื่มน้ำ (Smart Cup AI)
    จงวิเคราะห์ข้อมูลนี้:
    {user_context}

    ตอบกลับมาเป็น JSON ตามรูปแบบนี้เท่านั้น:
    {{
      "avg_intake": {today_total},
      "percent_target": {min(int((today_total / 2000) * 100), 100)},
      "health_score": <คะแนนสุขภาพ 0-100>,
      "consistency": <คะแนนความสม่ำเสมอ 0-100>,
      "tips": [
        {{
          "icon_type": "<เลือก sunny, fire, coffee หรือ alert>",
          "title": "<หัวข้อคำแนะนำสั้นๆ>",
          "description": "<คำแนะนำภาษาไทยสั้นๆ ไม่เกิน 2 ประโยค>"
        }}
      ]
    }}
    (สร้าง tips แนะนำ 2-3 ข้อ)
    """

    response = client.models.generate_content(
        model='gemini-3.8-flash',
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
        ),
    )

    result_json = json.loads(response.text)
    print("ผลลัพธ์จาก AI:")
    print(json.dumps(result_json, indent=2, ensure_ascii=False))

    ai_insights_ref = db.reference('SmartCup/ai_insights')
    ai_insights_ref.set(result_json)
    print("✅ อัปเดตข้อมูลสำเร็จแล้ว!")

if __name__ == '__main__':
    run_ai_analysis()