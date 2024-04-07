
import 'package:cloud_firestore/cloud_firestore.dart';

class FireStoreService {

  Future<void> uploadMapDataToFirestore(Map<String, dynamic> data, DocumentReference documentReference) async {
    try {
      // Convert GeoPoint values to Firestore GeoPoint objects
      data.forEach((key, value) {
        if (value is GeoPoint) {
          data[key] = value;
        }
      });

      await documentReference.set(data, SetOptions(merge: true));
      print('Map data uploaded successfully to Firestore!');
    } on FirebaseException catch (e) {
      print('Firestore Error: ${e.code} - ${e.message}');
      // Handle specific Firestore error
      if (e.code == 'permission-denied') {
        // Handle permission denied error
      } else {
        // Handle other Firestore errors
      }
    } catch (e) {
      print('Error uploading map data to Firestore: $e');
      // Handle generic error
    }
  }

  Future<List<String>> getDocumentNames(CollectionReference collectionReference) async {
    try {
      // Query the Firestore collection
      QuerySnapshot querySnapshot = await collectionReference.get();

      // Extract document names from the query snapshot
      List<String> documentNames = querySnapshot.docs.map((doc) => doc.id).toList();

      return documentNames;
    } catch (e) {
      // Handle any errors that occur
      print('Error retrieving document names: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getDocumentDetails(DocumentReference documentReference) async {
    try {
      // Get the document snapshot using the provided document reference
      DocumentSnapshot documentSnapshot = await documentReference.get();

      // Check if the document exists
      if (documentSnapshot.exists) {
        // Convert the document snapshot data to a map
        Map<String, dynamic> documentData = documentSnapshot.data() as Map<String, dynamic>;

        // Return the document details map
        return documentData;
      } else {
        // If document doesn't exist, return null
        return null;
      }
    } catch (error) {
      // Handle errors
      print('Error fetching document details: $error');
      return null;
    }
  }

  void deleteFieldsFromDocument(DocumentReference docRef, List<String> fieldNames) {
    Map<String, dynamic> updates = {};
    for (String fieldName in fieldNames) {
      updates[fieldName] = FieldValue.delete();
    }

    // Use update method to delete the fields
    docRef.update(updates).then((_) {
      print('Fields $fieldNames deleted successfully');
    }).catchError((error) {
      print('Error deleting fields $fieldNames: $error');
    });
  }

}
