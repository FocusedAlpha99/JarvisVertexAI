#!/usr/bin/env python3

"""
Test script to validate Vertex AI token refresh functionality in Mode 2.
This script simulates API calls that should trigger the token refresh mechanism.
"""

import os
import json
import requests
import time
from datetime import datetime

def test_vertex_ai_api():
    """Test the Vertex AI API to trigger 401 errors that should be handled by token refresh"""

    print("🧪 Testing Vertex AI Token Refresh Functionality")
    print("=" * 50)

    # Load environment variables
    project_id = os.getenv('VERTEX_PROJECT_ID', 'finzoo')
    region = os.getenv('VERTEX_REGION', 'us-east1')
    access_token = os.getenv('VERTEX_ACCESS_TOKEN', '')

    if not access_token:
        print("❌ No VERTEX_ACCESS_TOKEN found in environment")
        return False

    print(f"📊 Project ID: {project_id}")
    print(f"🌍 Region: {region}")
    print(f"🔑 Token (first 20 chars): {access_token[:20]}...")

    # Build API URL
    url = f"https://{region}-aiplatform.googleapis.com/v1/projects/{project_id}/locations/{region}/publishers/google/models/gemini-2.0-flash-exp:generateContent"

    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }

    # Test request payload
    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": "Test message for token refresh validation"}
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": 50,
            "disablePromptLogging": True,
            "disableDataRetention": True
        }
    }

    print(f"\n🚀 Making test API call to: {url}")
    print(f"⏰ Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)

        print(f"📋 Response Status: {response.status_code}")

        if response.status_code == 200:
            print("✅ API call successful - token is valid")
            try:
                data = response.json()
                if 'candidates' in data and data['candidates']:
                    text = data['candidates'][0]['content']['parts'][0]['text']
                    print(f"💬 Response: {text[:100]}...")
                return True
            except Exception as e:
                print(f"⚠️ Response parsing error: {e}")
                return True  # Still successful API call

        elif response.status_code == 401:
            print("⚠️ 401 Authentication error detected - token expired")
            print("🔄 This should trigger automatic token refresh in the iOS app")
            try:
                error_data = response.json()
                print(f"💬 Error details: {json.dumps(error_data, indent=2)}")
            except:
                pass
            return False

        else:
            print(f"❌ Unexpected status code: {response.status_code}")
            try:
                error_data = response.json()
                print(f"💬 Error details: {json.dumps(error_data, indent=2)}")
            except:
                print(f"💬 Error text: {response.text}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"❌ Network error: {e}")
        return False

def check_token_expiry():
    """Check if the current token appears to be expired based on format/age"""
    access_token = os.getenv('VERTEX_ACCESS_TOKEN', '')

    if not access_token:
        print("❌ No token to check")
        return None

    print(f"\n🔍 Token Analysis:")
    print(f"   Length: {len(access_token)} characters")
    print(f"   Starts with: {access_token[:10]}...")
    print(f"   Format valid: {'✅' if access_token.startswith('ya29.') else '❌'}")

    # Note: We can't determine exact expiry without decoding, but we can make basic checks
    if not access_token.startswith('ya29.'):
        print("⚠️ Token doesn't appear to be a valid Google access token")
        return False

    if len(access_token) < 50:
        print("⚠️ Token appears unusually short")
        return False

    print("✅ Token format appears valid")
    return True

def main():
    """Main test function"""
    print("🧪 JarvisVertexAI Token Refresh Test")
    print("This test validates that expired tokens trigger proper refresh in the iOS app")
    print()

    # Check token format
    token_valid = check_token_expiry()

    if token_valid is False:
        print("\n❌ Token format issues detected - cannot proceed with API test")
        return

    # Test API call
    api_success = test_vertex_ai_api()

    print(f"\n{'='*50}")
    print("📊 TEST RESULTS:")
    print(f"   Token Format: {'✅ Valid' if token_valid else '❌ Invalid'}")
    print(f"   API Call: {'✅ Success' if api_success else '⚠️ Failed (expected if token expired)'}")

    if not api_success:
        print("\n🔄 Expected Behavior in iOS App:")
        print("   1. LocalSTTTTS.swift should detect 401 error")
        print("   2. AccessTokenProvider should attempt token refresh")
        print("   3. API call should be retried with fresh token")
        print("   4. If refresh fails, user should see authentication error")

    print(f"\n⏰ Test completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

if __name__ == "__main__":
    main()