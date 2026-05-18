#!/usr/bin/env python3
"""
ABAC Resource Isolation Test

This script verifies that Attribute-Based Access Control (ABAC) properly isolates
resources between different users in an OGX deployment.

Tests that:
1. Users can create and access their own resources
2. Users are denied access to other users' resources
3. List endpoints properly filter resources by ownership

Usage:
    uv run demos/tests/abac_isolation/demo.py
"""

import os
import sys
import json
import io
from typing import Optional, Dict, Any, List
from pathlib import Path
from openai import OpenAI

# Add project root to path for imports
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from demos.common.utils import get_keycloak_token, load_demo_config
from scripts.read_k8s import get_secret


class ABACIsolationTest:
    def __init__(self, base_url: str, keycloak_url: str, client_secret: str, password: str):
        self.base_url = base_url.rstrip('/')
        self.keycloak_url = keycloak_url.rstrip('/')
        self.client_secret = client_secret
        self.password = password

        # Track created resources by user
        self.resources = {
            'developer': {
                'vector_stores': [],
                'files': [],
                'responses': [],
                'conversations': []
            },
            'user': {
                'vector_stores': [],
                'files': [],
                'responses': [],
                'conversations': []
            }
        }

        # Track test results
        self.tests_passed = 0
        self.tests_failed = 0
        self.errors = []

        # OpenAI clients for each user
        self.clients = {}

    @staticmethod
    def _parse_error_status(e: Exception) -> int:
        """Extract HTTP status code from an OpenAI SDK exception."""
        if hasattr(e, 'status_code'):
            return e.status_code
        error_str = str(e)
        for code, keywords in [(403, ['403', 'Forbidden']), (404, ['404', 'Not Found']), (400, ['400', 'Bad Request'])]:
            if any(k in error_str for k in keywords):
                return code
        return 0

    def authenticate_user(self, username: str) -> Optional[OpenAI]:
        """Authenticate a user and return OpenAI client"""
        try:
            print(f"\n🔐 Authenticating as '{username}'...")
            access_token = get_keycloak_token(
                self.keycloak_url,
                username,
                self.password,
                self.client_secret,
                verbose=False
            )

            client = OpenAI(
                base_url=f"{self.base_url}/v1",
                api_key=access_token,
            )

            print(f"✓ Authentication successful for '{username}'")
            return client

        except Exception as e:
            print(f"✗ Authentication failed for '{username}': {e}")
            return None

    def create_vector_store(self, client: OpenAI, username: str, name: str) -> Optional[str]:
        """Create a vector store and track it"""
        try:
            # Use the OpenAI client's base functionality with direct HTTP call
            # Since OpenAI SDK doesn't have native vector_stores, we'll use the HTTP session
            import requests

            session = requests.Session()
            session.headers.update({'Authorization': f'Bearer {client.api_key}'})

            payload = {
                "vector_store_id": name,
                "embedding_model": "vllm-embedding/nomic-embed-text-v1.5",
                "embedding_dimension": 768,
                "provider_id": "milvus-remote"
            }

            response = session.post(
                f"{self.base_url}/v1/vector_stores",
                json=payload,
                headers={"Content-Type": "application/json"},
                verify=True
            )

            if response.status_code in [200, 201]:
                result = response.json()
                vector_store_id = result.get('id')
                self.resources[username]['vector_stores'].append(vector_store_id)
                print(f"  ✓ Created vector store: {vector_store_id}")
                return vector_store_id
            else:
                print(f"  ✗ Failed to create vector store: {response.status_code}")
                return None

        except Exception as e:
            print(f"  ✗ Error creating vector store: {e}")
            return None

    def get_vector_store(self, client: OpenAI, vector_store_id: str) -> tuple[bool, int]:
        """Try to get a vector store, return (success, status_code)"""
        try:
            import requests

            session = requests.Session()
            session.headers.update({'Authorization': f'Bearer {client.api_key}'})

            response = session.get(
                f"{self.base_url}/v1/vector_stores/{vector_store_id}",
                verify=True
            )

            return (response.status_code in [200, 201], response.status_code)

        except Exception as e:
            return (False, 0)

    def delete_vector_store(self, client: OpenAI, vector_store_id: str) -> tuple[bool, int]:
        """Try to delete a vector store, return (success, status_code)"""
        try:
            import requests

            session = requests.Session()
            session.headers.update({'Authorization': f'Bearer {client.api_key}'})

            response = session.delete(
                f"{self.base_url}/v1/vector_stores/{vector_store_id}",
                verify=True
            )

            return (response.status_code in [200, 204], response.status_code)

        except Exception as e:
            return (False, 0)

    def upload_file(self, client: OpenAI, username: str, filename: str, content: str) -> Optional[str]:
        """Upload a file using OpenAI client"""
        try:
            # Create a file-like object from the content
            file_content = io.BytesIO(content.encode('utf-8'))
            file_content.name = filename

            # Use OpenAI client's files.create
            file_obj = client.files.create(
                file=file_content,
                purpose="assistants"
            )

            file_id = file_obj.id
            self.resources[username]['files'].append(file_id)
            print(f"  ✓ Uploaded file: {filename} (ID: {file_id})")
            return file_id

        except Exception as e:
            print(f"  ✗ Error uploading file: {e}")
            return None

    def get_file(self, client: OpenAI, file_id: str) -> tuple[bool, int]:
        """Try to get a file, return (success, status_code)"""
        try:
            file_obj = client.files.retrieve(file_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def delete_file(self, client: OpenAI, file_id: str) -> tuple[bool, int]:
        """Try to delete a file, return (success, status_code)"""
        try:
            client.files.delete(file_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def create_response(self, client: OpenAI, username: str, input_text: str,
                       instructions: str, stream: bool = False) -> Optional[str]:
        """Create a response (streaming or non-streaming) and track it"""
        try:
            params = {
                "model": "vllm-inference/llama-3-2-3b",
                "input": input_text,
                "instructions": instructions,
                "store": True
            }

            if stream:
                params["stream"] = True
                response_stream = client.responses.create(**params)

                # Parse SSE stream to extract response_id
                response_id = None
                for chunk in response_stream:
                    # The chunk should be a response object
                    if hasattr(chunk, 'id') and chunk.id:
                        response_id = chunk.id
                        break
                    # Check for response field
                    if hasattr(chunk, 'response') and hasattr(chunk.response, 'id'):
                        response_id = chunk.response.id
                        break

                if response_id:
                    self.resources[username]['responses'].append(response_id)
                    print(f"  ✓ Created streaming response: {response_id}")
                    return response_id
                else:
                    print(f"  ✗ Could not extract response_id from stream")
                    return None
            else:
                response = client.responses.create(**params)
                response_id = response.id
                self.resources[username]['responses'].append(response_id)
                print(f"  ✓ Created response: {response_id}")
                return response_id

        except Exception as e:
            print(f"  ✗ Error creating response: {e}")
            return None

    def get_response(self, client: OpenAI, response_id: str) -> tuple[bool, int]:
        """Try to get a response, return (success, status_code)"""
        try:
            response = client.responses.retrieve(response_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def list_responses(self, client: OpenAI, limit: int = 10) -> List[str]:
        """List responses, return list of response IDs"""
        try:
            import requests

            session = requests.Session()
            session.headers.update({'Authorization': f'Bearer {client.api_key}'})

            response = session.get(
                f"{self.base_url}/v1/responses",
                params={'limit': limit},
                verify=True
            )

            if response.status_code == 200:
                result = response.json()
                # Extract IDs from data array
                if 'data' in result:
                    return [r['id'] for r in result['data']]
                return []
            else:
                print(f"  ✗ Error listing responses: {response.status_code}")
                return []
        except Exception as e:
            print(f"  ✗ Error listing responses: {e}")
            return []

    def get_response_input_items(self, client: OpenAI, response_id: str) -> tuple[bool, int]:
        """Try to get response input items, return (success, status_code)"""
        try:
            import requests

            session = requests.Session()
            session.headers.update({'Authorization': f'Bearer {client.api_key}'})

            response = session.get(
                f"{self.base_url}/v1/responses/{response_id}/input_items",
                verify=True
            )

            return (response.status_code == 200, response.status_code)

        except Exception as e:
            return (False, 0)

    def delete_response(self, client: OpenAI, response_id: str) -> tuple[bool, int]:
        """Try to delete a response, return (success, status_code)"""
        try:
            client.responses.delete(response_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def create_conversation(self, client: OpenAI, username: str, name: str) -> Optional[str]:
        """Create a conversation and track it"""
        try:
            conversation = client.conversations.create(
                metadata={"owner": username, "name": name}
            )
            conversation_id = conversation.id
            self.resources[username]['conversations'].append(conversation_id)
            print(f"  ✓ Created conversation: {name} (ID: {conversation_id})")
            return conversation_id
        except Exception as e:
            print(f"  ✗ Error creating conversation: {e}")
            return None

    def get_conversation(self, client: OpenAI, conversation_id: str) -> tuple[bool, int]:
        """Try to get a conversation, return (success, status_code)"""
        try:
            client.conversations.retrieve(conversation_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def update_conversation(self, client: OpenAI, conversation_id: str, name: str) -> tuple[bool, int]:
        """Try to update a conversation, return (success, status_code)"""
        try:
            client.conversations.update(
                conversation_id,
                metadata={"name": name}
            )
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def delete_conversation(self, client: OpenAI, conversation_id: str) -> tuple[bool, int]:
        """Try to delete a conversation, return (success, status_code)"""
        try:
            client.conversations.delete(conversation_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def add_conversation_item(self, client: OpenAI, conversation_id: str, content: str, role: str = "user") -> Optional[str]:
        """Add an item to a conversation, return item_id"""
        try:
            # items.create expects an iterable of items
            result = client.conversations.items.create(
                conversation_id,
                items=[{
                    "role": role,
                    "content": content
                }]
            )
            # Return first item ID from the created items
            if hasattr(result, 'data') and len(result.data) > 0:
                item_id = result.data[0].id
                print(f"  ✓ Added item to conversation {conversation_id}: {item_id}")
                return item_id
            else:
                print(f"  ✗ No items returned from create")
                return None
        except Exception as e:
            print(f"  ✗ Error adding conversation item: {e}")
            return None

    def get_conversation_item(self, client: OpenAI, conversation_id: str, item_id: str) -> tuple[bool, int]:
        """Try to get a conversation item, return (success, status_code)"""
        try:
            client.conversations.items.retrieve(item_id, conversation_id=conversation_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def list_conversation_items(self, client: OpenAI, conversation_id: str) -> tuple[bool, int, List[str]]:
        """Try to list conversation items, return (success, status_code, item_ids)"""
        try:
            items_page = client.conversations.items.list(conversation_id)
            item_ids = [item.id for item in items_page.data] if hasattr(items_page, 'data') else []
            return (True, 200, item_ids)
        except Exception as e:
            return (False, self._parse_error_status(e), [])

    def delete_conversation_item(self, client: OpenAI, conversation_id: str, item_id: str) -> tuple[bool, int]:
        """Try to delete a conversation item, return (success, status_code)"""
        try:
            client.conversations.items.delete(item_id, conversation_id=conversation_id)
            return (True, 200)
        except Exception as e:
            return (False, self._parse_error_status(e))

    def test_access(self, description: str, should_succeed: bool, success: bool, status_code: int):
        """Track a test result"""
        if should_succeed:
            if success:
                self.tests_passed += 1
                print(f"  ✓ {description}: PASS (allowed)")
            else:
                self.tests_failed += 1
                error_msg = f"{description}: FAIL - Expected success, got {status_code}"
                self.errors.append(error_msg)
                print(f"  ✗ {error_msg}")
        else:
            # Should be denied
            if not success and status_code in [400, 403, 404]:
                self.tests_passed += 1
                print(f"  ✓ {description}: PASS (denied with {status_code})")
            else:
                self.tests_failed += 1
                if success:
                    error_msg = f"{description}: FAIL - Expected denial, but succeeded"
                else:
                    error_msg = f"{description}: FAIL - Expected denial (403/400/404), got {status_code}"
                self.errors.append(error_msg)
                print(f"  ✗ {error_msg}")

    def run_test(self):
        """Run the complete ABAC isolation test"""
        print("=" * 70)
        print("ABAC Resource Isolation Test")
        print("=" * 70)

        # Step 1: Authentication
        print("\n" + "=" * 70)
        print("Step 1: Authentication")
        print("=" * 70)

        self.clients['developer'] = self.authenticate_user('developer')
        self.clients['user'] = self.authenticate_user('user')

        if not self.clients['developer'] or not self.clients['user']:
            print("\n✗ Authentication failed. Cannot continue test.")
            return False

        # Step 2: Developer Creates Resources
        print("\n" + "=" * 70)
        print("Step 2: Developer Creates Resources")
        print("=" * 70)

        print("\nCreating vector store...")
        dev_vector_store = self.create_vector_store(
            self.clients['developer'],
            'developer',
            'developer-private-store'
        )

        print("\nCreating file...")
        file_content = """Confidential ML Project Data

This document contains proprietary information about our machine learning project.
The data includes model architectures, training datasets, and performance metrics.
This information is confidential and should not be shared outside the development team.
"""
        dev_file = self.upload_file(
            self.clients['developer'],
            'developer',
            'developer-private-data.txt',
            file_content
        )

        print("\nCreating non-streaming response...")
        dev_response1 = self.create_response(
            self.clients['developer'],
            'developer',
            'What is a vector database?',
            'You are a helpful assistant. Be brief.',
            stream=False
        )

        print("\nCreating streaming response...")
        dev_response2 = self.create_response(
            self.clients['developer'],
            'developer',
            'What is semantic search?',
            'You are a helpful assistant. Be brief.',
            stream=True
        )

        print("\nCreating conversation...")
        dev_conversation = self.create_conversation(
            self.clients['developer'],
            'developer',
            'developer-private-chat'
        )

        print("\nAdding items to conversation...")
        dev_conv_item1 = None
        dev_conv_item2 = None
        if dev_conversation:
            dev_conv_item1 = self.add_conversation_item(
                self.clients['developer'],
                dev_conversation,
                'What are the security considerations for our ML pipeline?',
                'user'
            )
            dev_conv_item2 = self.add_conversation_item(
                self.clients['developer'],
                dev_conversation,
                'Security is critical for ML pipelines.',
                'assistant'
            )

        if not all([dev_vector_store, dev_file, dev_response1, dev_response2, dev_conversation, dev_conv_item1, dev_conv_item2]):
            print("\n✗ Failed to create all developer resources. Cannot continue test.")
            return False

        # Step 3: Developer Verifies Own Access
        print("\n" + "=" * 70)
        print("Step 3: Developer Verifies Own Access")
        print("=" * 70)

        success, status = self.get_vector_store(self.clients['developer'], dev_vector_store)
        self.test_access("Developer READ own vector store", True, success, status)

        success, status = self.get_file(self.clients['developer'], dev_file)
        self.test_access("Developer READ own file", True, success, status)

        success, status = self.get_response(self.clients['developer'], dev_response1)
        self.test_access("Developer READ own response", True, success, status)

        dev_responses = self.list_responses(self.clients['developer'])
        if len(dev_responses) >= 2:
            self.tests_passed += 1
            print(f"  ✓ Developer LIST responses: PASS (found {len(dev_responses)} responses)")
        else:
            self.tests_failed += 1
            print(f"  ✗ Developer LIST responses: FAIL (expected >=2, found {len(dev_responses)})")

        success, status = self.get_response_input_items(self.clients['developer'], dev_response1)
        self.test_access("Developer LIST response input items", True, success, status)

        success, status = self.get_conversation(self.clients['developer'], dev_conversation)
        self.test_access("Developer READ own conversation", True, success, status)

        success, status = self.update_conversation(self.clients['developer'], dev_conversation, 'developer-updated-chat')
        self.test_access("Developer UPDATE own conversation", True, success, status)

        success, status = self.get_conversation_item(self.clients['developer'], dev_conversation, dev_conv_item1)
        self.test_access("Developer READ own conversation item", True, success, status)

        success, status, items = self.list_conversation_items(self.clients['developer'], dev_conversation)
        self.test_access("Developer LIST own conversation items", True, success, status)
        if success and len(items) >= 2:
            print(f"    (found {len(items)} items)")
        elif success:
            print(f"    ⚠ Warning: expected >=2 items, found {len(items)}")

        # Step 3b: User Creates Own Resources
        print("\n" + "=" * 70)
        print("Step 3b: User Creates Own Resources")
        print("=" * 70)

        print("\nCreating user's response...")
        user_response = self.create_response(
            self.clients['user'],
            'user',
            'What is machine learning?',
            'You are a helpful assistant. Be brief.',
            stream=False
        )

        print("\nCreating user's conversation...")
        user_conversation = self.create_conversation(
            self.clients['user'],
            'user',
            'user-private-chat'
        )

        print("\nAdding item to user's conversation...")
        user_conv_item = None
        if user_conversation:
            user_conv_item = self.add_conversation_item(
                self.clients['user'],
                user_conversation,
                'Tell me about AI safety',
                'user'
            )

        if not all([user_response, user_conversation, user_conv_item]):
            print("\n✗ Failed to create user resources. Cannot continue test.")
            return False

        # Step 3c: Verify List Filtering
        print("\n" + "=" * 70)
        print("Step 3c: Verify List Filtering")
        print("=" * 70)

        print("\nChecking developer's response list...")
        dev_list = self.list_responses(self.clients['developer'])
        dev_has_own = dev_response1 in dev_list and dev_response2 in dev_list
        dev_has_user = user_response in dev_list

        if dev_has_own and not dev_has_user:
            self.tests_passed += 1
            print(f"  ✓ Developer list filtering: PASS (has own, not user's)")
        else:
            self.tests_failed += 1
            if not dev_has_own:
                print(f"  ✗ Developer list filtering: FAIL (missing own responses)")
            if dev_has_user:
                print(f"  ✗ Developer list filtering: FAIL (includes user's response)")

        print("\nChecking user's response list...")
        user_list = self.list_responses(self.clients['user'])
        user_has_own = user_response in user_list
        user_has_dev = dev_response1 in user_list or dev_response2 in user_list

        if user_has_own and not user_has_dev:
            self.tests_passed += 1
            print(f"  ✓ User list filtering: PASS (has own, not developer's)")
        else:
            self.tests_failed += 1
            if not user_has_own:
                print(f"  ✗ User list filtering: FAIL (missing own response)")
            if user_has_dev:
                print(f"  ✗ User list filtering: FAIL (includes developer's responses)")

        # Step 4: Verify User Cannot Access Developer Resources
        print("\n" + "=" * 70)
        print("Step 4: Verify User Cannot Access Developer Resources")
        print("=" * 70)

        success, status = self.get_vector_store(self.clients['user'], dev_vector_store)
        self.test_access("User READ developer's vector store", False, success, status)

        success, status = self.get_file(self.clients['user'], dev_file)
        self.test_access("User READ developer's file", False, success, status)

        success, status = self.get_response(self.clients['user'], dev_response1)
        self.test_access("User READ developer's response", False, success, status)

        success, status = self.get_response_input_items(self.clients['user'], dev_response1)
        self.test_access("User LIST developer's response input items", False, success, status)

        success, status = self.delete_vector_store(self.clients['user'], dev_vector_store)
        self.test_access("User DELETE developer's vector store", False, success, status)

        success, status = self.delete_file(self.clients['user'], dev_file)
        self.test_access("User DELETE developer's file", False, success, status)

        success, status = self.delete_response(self.clients['user'], dev_response1)
        self.test_access("User DELETE developer's response", False, success, status)

        success, status = self.get_conversation(self.clients['user'], dev_conversation)
        self.test_access("User READ developer's conversation", False, success, status)

        success, status = self.update_conversation(self.clients['user'], dev_conversation, 'user-hacked-chat')
        self.test_access("User UPDATE developer's conversation", False, success, status)

        success, status = self.get_conversation_item(self.clients['user'], dev_conversation, dev_conv_item1)
        self.test_access("User READ developer's conversation item", False, success, status)

        success, status, items = self.list_conversation_items(self.clients['user'], dev_conversation)
        self.test_access("User LIST developer's conversation items", False, success, status)

        if dev_conv_item1:
            success, status = self.delete_conversation_item(self.clients['user'], dev_conversation, dev_conv_item1)
            self.test_access("User DELETE developer's conversation item", False, success, status)

        success, status = self.delete_conversation(self.clients['user'], dev_conversation)
        self.test_access("User DELETE developer's conversation", False, success, status)

        # Step 5: Cleanup
        print("\n" + "=" * 70)
        print("Step 5: Cleanup")
        print("=" * 70)

        print("\nDeveloper cleaning up resources...")
        for vs_id in self.resources['developer']['vector_stores']:
            success, status = self.delete_vector_store(self.clients['developer'], vs_id)
            if success:
                print(f"  ✓ Deleted vector store: {vs_id}")
            else:
                print(f"  ✗ Failed to delete vector store: {vs_id} ({status})")

        for file_id in self.resources['developer']['files']:
            success, status = self.delete_file(self.clients['developer'], file_id)
            if success:
                print(f"  ✓ Deleted file: {file_id}")
            else:
                print(f"  ✗ Failed to delete file: {file_id} ({status})")

        for response_id in self.resources['developer']['responses']:
            success, status = self.delete_response(self.clients['developer'], response_id)
            if success:
                print(f"  ✓ Deleted response: {response_id}")
            else:
                print(f"  ✗ Failed to delete response: {response_id} ({status})")

        for conversation_id in self.resources['developer']['conversations']:
            success, status = self.delete_conversation(self.clients['developer'], conversation_id)
            if success:
                print(f"  ✓ Deleted conversation: {conversation_id}")
            else:
                print(f"  ✗ Failed to delete conversation: {conversation_id} ({status})")

        print("\nUser cleaning up resources...")
        for response_id in self.resources['user']['responses']:
            success, status = self.delete_response(self.clients['user'], response_id)
            if success:
                print(f"  ✓ Deleted response: {response_id}")
            else:
                print(f"  ✗ Failed to delete response: {response_id} ({status})")

        for conversation_id in self.resources['user']['conversations']:
            success, status = self.delete_conversation(self.clients['user'], conversation_id)
            if success:
                print(f"  ✓ Deleted conversation: {conversation_id}")
            else:
                print(f"  ✗ Failed to delete conversation: {conversation_id} ({status})")

        # Print summary
        print("\n" + "=" * 70)
        print("Test Summary")
        print("=" * 70)

        total = self.tests_passed + self.tests_failed
        print(f"\nTotal tests: {total}")
        print(f"Passed: {self.tests_passed}")
        print(f"Failed: {self.tests_failed}")

        if self.errors:
            print("\nErrors:")
            for error in self.errors:
                print(f"  - {error}")

        if self.tests_failed == 0:
            print("\n" + "=" * 70)
            print("✅ ALL TESTS PASSED")
            print("=" * 70)
            print("\nResource isolation is working correctly:")
            print("  - 'developer' can create and access their own resources")
            print("  - 'user' is denied all access to 'developer' resources")
            print("  - ABAC ownership policy is properly enforced")
            print("\nTested resource types:")
            print("  - Vector stores (for embeddings and semantic search)")
            print("  - Files (uploaded documents)")
            print("  - Responses (AI conversations)")
            print("  - Conversations (multi-turn dialogues)")
            print("\nTested response endpoints:")
            print("  - POST /v1/responses (create response)")
            print("  - POST /v1/responses (streaming response)")
            print("  - GET /v1/responses/{id} (retrieve response)")
            print("  - GET /v1/responses (list responses)")
            print("  - GET /v1/responses (list filtering - users only see own)")
            print("  - GET /v1/responses/{id}/input_items (list input items)")
            print("  - DELETE /v1/responses/{id} (delete response)")
            print("\nTested conversation endpoints:")
            print("  - POST /v1/conversations (create conversation)")
            print("  - GET /v1/conversations/{id} (retrieve conversation)")
            print("  - POST /v1/conversations/{id} (update conversation)")
            print("  - DELETE /v1/conversations/{id} (delete conversation)")
            print("  - POST /v1/conversations/{id}/items (add item)")
            print("  - GET /v1/conversations/{id}/items/{item_id} (get item)")
            print("  - GET /v1/conversations/{id}/items (list items)")
            print("  - DELETE /v1/conversations/{id}/items/{item_id} (delete item)")
            return True
        else:
            print("\n" + "=" * 70)
            print("❌ TESTS FAILED")
            print("=" * 70)
            return False


def main():
    # Load configuration
    config = load_demo_config()

    ogx_url = config['ogx_url']
    keycloak_url = config['keycloak_url']
    client_secret = config['client_secret']

    # Get demo password from K8s or env var
    password = os.environ.get('KEYCLOAK_DEMO_PASSWORD') or get_secret('keycloak-secret', 'KEYCLOAK_DEMO_PASSWORD')

    # Validate required configuration
    if not ogx_url:
        print("Error: OGX_URL is required")
        print("Set it as an environment variable or ensure oc is logged in to the cluster")
        sys.exit(1)

    if not keycloak_url:
        print("Error: KEYCLOAK_URL is required for this test")
        print("Set it as an environment variable or ensure oc is logged in to the cluster")
        sys.exit(1)

    if not client_secret:
        print("Error: KEYCLOAK_CLIENT_SECRET is required for this test")
        print("Set it as an environment variable or ensure oc is logged in to the cluster")
        sys.exit(1)

    if not password:
        print("Error: KEYCLOAK_DEMO_PASSWORD is required for this test")
        print("Ensure oc is logged in to the cluster, or set the password manually:")
        print("  export KEYCLOAK_DEMO_PASSWORD=your-password")
        sys.exit(1)

    # Run the test
    test = ABACIsolationTest(ogx_url, keycloak_url, client_secret, password)
    success = test.run_test()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
